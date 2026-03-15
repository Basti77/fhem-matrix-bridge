package main;

use strict;
use warnings;
use HttpUtils;
use JSON qw(decode_json encode_json);
use MIME::Base64 qw(encode_base64);
use Encode qw(decode_utf8 encode_utf8);
use Time::HiRes qw(gettimeofday);

sub plotAsPng(@);
sub Signalbot_getPNG(@);

sub MatrixBridge_Initialize($);
sub MatrixBridge_Define($$);
sub MatrixBridge_Undef($$);
sub MatrixBridge_Set($@);
sub MatrixBridge_Attr(@);
sub MatrixBridge_Login($;$);
sub MatrixBridge_Send($$$$);
sub MatrixBridge_SendImage($$$$;$);
sub MatrixBridge_SendPlot($$$$);
sub MatrixBridge_HttpNonblocking($$$$);
sub MatrixBridge_LoginCallback($$$);
sub MatrixBridge_SendCallback($$$);
sub MatrixBridge_UploadCallback($$$);
sub MatrixBridge__room_for_target($$);
sub MatrixBridge__json_error($);
sub MatrixBridge__store_token($$);
sub MatrixBridge__load_token($);
sub MatrixBridge__token_file($);
sub MatrixBridge__urlencode($);
sub MatrixBridge__write_temp_file($$$);
sub MatrixBridge__content_type_for($);

sub MatrixBridge_Initialize($) {
  my ($hash) = @_;
  $hash->{DefFn}    = 'MatrixBridge_Define';
  $hash->{UndefFn}  = 'MatrixBridge_Undef';
  $hash->{SetFn}    = 'MatrixBridge_Set';
  $hash->{AttrFn}   = 'MatrixBridge_Attr';
  $hash->{AttrList} = 'matrixBaseUrl matrixUser matrixPassword roomMap defaultTarget tokenFile autoLogin:0,1 disableTLSCheck:0,1 verbose:0,1';
}

sub MatrixBridge_Define($$) {
  my ($hash, $def) = @_;
  my @a = split(/\s+/, $def, 3);
  return 'Usage: define <name> MatrixBridge' if @a < 2;

  $hash->{STATE} = 'defined';
  readingsSingleUpdate($hash, 'state', 'defined', 1);
  readingsSingleUpdate($hash, 'lastError', '-', 1);
  readingsSingleUpdate($hash, 'lastResult', '-', 1);

  if (AttrVal($hash->{NAME}, 'autoLogin', 1)) {
    MatrixBridge_Login($hash, 1);
  }
  return undef;
}

sub MatrixBridge_Undef($$) {
  my ($hash, $arg) = @_;
  RemoveInternalTimer($hash);
  return undef;
}

sub MatrixBridge_Set($@) {
  my ($hash, @a) = @_;
  return 'Need at least one argument' if @a < 2;

  my $name = shift @a;
  my $cmd  = shift @a;

  if ($cmd eq 'login') {
    return MatrixBridge_Login($hash, 0);
  }
  elsif ($cmd eq 'logout') {
    delete $hash->{helper}{access_token};
    MatrixBridge__store_token($hash, '');
    readingsSingleUpdate($hash, 'state', 'logged_out', 1);
    return undef;
  }
  elsif ($cmd eq 'send') {
    return 'Usage: set <name> send <target> <message text>' if @a < 2;
    my $target = shift @a;
    my $message = join(' ', @a);
    return MatrixBridge_Send($hash, $target, $message, 'm.text');
  }
  elsif ($cmd eq 'sendNotice') {
    return 'Usage: set <name> sendNotice <target> <message text>' if @a < 2;
    my $target = shift @a;
    my $message = join(' ', @a);
    return MatrixBridge_Send($hash, $target, $message, 'm.notice');
  }
  elsif ($cmd eq 'sendImage') {
    return 'Usage: set <name> sendImage <target> <file path> [caption]' if @a < 2;
    my $target = shift @a;
    my $file = shift @a;
    my $caption = join(' ', @a);
    return MatrixBridge_SendImage($hash, $target, $file, $caption, undef);
  }
  elsif ($cmd eq 'sendPlot') {
    return 'Usage: set <name> sendPlot <target> <svg device name> [caption]' if @a < 2;
    my $target = shift @a;
    my $plot = shift @a;
    my $caption = join(' ', @a);
    return MatrixBridge_SendPlot($hash, $target, $plot, $caption);
  }

  return 'Unknown argument ' . $cmd . ', choose one of login:noArg logout:noArg send sendNotice sendImage sendPlot';
}

sub MatrixBridge_Attr(@) {
  my ($cmd, $name, $attrName, $attrValue) = @_;
  my $hash = $defs{$name};

  if ($cmd eq 'set' && $attrName eq 'autoLogin' && $attrValue) {
    MatrixBridge_Login($hash, 1);
  }
  return undef;
}

sub MatrixBridge_Login($;$) {
  my ($hash, $silent) = @_;
  my $name = $hash->{NAME};

  my $base = AttrVal($name, 'matrixBaseUrl', '');
  my $user = AttrVal($name, 'matrixUser', '');
  my $pass = AttrVal($name, 'matrixPassword', '');
  return 'matrixBaseUrl attribute missing' if !$base;
  return 'matrixUser attribute missing' if !$user;
  return 'matrixPassword attribute missing' if !$pass;

  my $body = encode_json({
    type => 'm.login.password',
    identifier => { type => 'm.id.user', user => $user },
    password => $pass,
  });

  readingsSingleUpdate($hash, 'state', 'logging_in', 1);
  MatrixBridge_HttpNonblocking($hash,
    {
      url => "$base/_matrix/client/v3/login",
      method => 'POST',
      header => 'Content-Type: application/json',
      data => $body,
      timeout => 15,
      ignoreTLS => AttrVal($name, 'disableTLSCheck', 0),
      callbackName => 'login',
    },
    \&MatrixBridge_LoginCallback,
    { silent => $silent }
  );
  return undef;
}

sub MatrixBridge_Send($$$$) {
  my ($hash, $target, $message, $msgtype) = @_;
  my $name = $hash->{NAME};

  if (defined $message && !utf8::is_utf8($message)) {
    eval { $message = decode_utf8($message, 1); };
  }
  my $base = AttrVal($name, 'matrixBaseUrl', '');
  return 'matrixBaseUrl attribute missing' if !$base;

  my $token = $hash->{helper}{access_token} || MatrixBridge__load_token($hash);
  if (!$token) {
    return 'No access token. Run: set ' . $name . ' login';
  }
  $hash->{helper}{access_token} = $token;

  my $room = MatrixBridge__room_for_target($hash, $target);
  return 'No room mapping found for target: ' . $target if !$room;

  my $txn = time() . '-' . int(rand(1000000));
  my $body = encode_json({ msgtype => $msgtype, body => $message });
  my $url  = $base . '/_matrix/client/v3/rooms/' . MatrixBridge__urlencode($room) . '/send/m.room.message/' . $txn . '?access_token=' . MatrixBridge__urlencode($token);

  readingsSingleUpdate($hash, 'state', 'sending', 1);
  MatrixBridge_HttpNonblocking($hash,
    {
      url => $url,
      method => 'PUT',
      header => 'Content-Type: application/json',
      data => $body,
      timeout => 15,
      ignoreTLS => AttrVal($name, 'disableTLSCheck', 0),
      callbackName => 'send',
    },
    \&MatrixBridge_SendCallback,
    {
      target => $target,
      room   => $room,
      body   => $message,
      msgtype => $msgtype,
    }
  );
  return undef;
}

sub MatrixBridge_HttpNonblocking($$$$) {
  my ($hash, $param, $callback, $ctx) = @_;
  $param->{hash} = $hash;
  $param->{callback} = sub {
    my ($p, $err, $data) = @_;
    $callback->($p, $err, $data, $ctx);
  };
  HttpUtils_NonblockingGet($param);
}

sub MatrixBridge_SendImage($$$$;$) {
  my ($hash, $target, $file, $caption, $mime) = @_;
  my $name = $hash->{NAME};
  my $base = AttrVal($name, 'matrixBaseUrl', '');
  return 'matrixBaseUrl attribute missing' if !$base;
  return 'File not found: ' . $file if !$file || !-f $file;

  my $token = $hash->{helper}{access_token} || MatrixBridge__load_token($hash);
  if (!$token) {
    return 'No access token. Run: set ' . $name . ' login';
  }
  $hash->{helper}{access_token} = $token;

  my $room = MatrixBridge__room_for_target($hash, $target);
  return 'No room mapping found for target: ' . $target if !$room;

  open(my $fh, '<', $file) or return 'Cannot open file: ' . $file;
  binmode($fh);
  local $/ = undef;
  my $data = <$fh>;
  close($fh);

  my $filename = $file;
  $filename =~ s{.*/}{};
  $mime ||= MatrixBridge__content_type_for($filename);
  my $display_body = defined($caption) && $caption ne '' ? $caption : $filename;
  my $upload_url = $base . '/_matrix/media/v3/upload?filename=' . MatrixBridge__urlencode($filename) . '&access_token=' . MatrixBridge__urlencode($token);

  readingsSingleUpdate($hash, 'state', 'uploading', 1);
  MatrixBridge_HttpNonblocking($hash,
    {
      url => $upload_url,
      method => 'POST',
      header => 'Content-Type: ' . $mime,
      data => $data,
      timeout => 60,
      ignoreTLS => AttrVal($name, 'disableTLSCheck', 0),
      callbackName => 'upload',
    },
    \&MatrixBridge_UploadCallback,
    {
      target => $target,
      room => $room,
      caption => $caption,
      display_body => $display_body,
      filename => $filename,
      mime => $mime,
      size => length($data),
    }
  );
  return undef;
}

sub MatrixBridge_SendPlot($$$$) {
  my ($hash, $target, $plot, $caption) = @_;

  my $png_file;
  if (defined &Signalbot_getPNG) {
    $png_file = eval { Signalbot_getPNG($hash, $plot) };
  } else {
    my $png = eval { plotAsPng($plot) };
    return 'plotAsPng failed for ' . $plot if !$png;
    return $png if $png =~ /^Error:/;
    $png_file = MatrixBridge__write_temp_file($hash, $png, 'png');
  }

  return 'Could not create plot PNG for ' . $plot if !$png_file || !-f $png_file;
  return MatrixBridge_SendImage($hash, $target, $png_file, '', 'image/png');
}

sub MatrixBridge_LoginCallback($$$) {
  my ($param, $err, $data, $ctx) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if ($err) {
    readingsSingleUpdate($hash, 'state', 'login_failed', 1);
    readingsSingleUpdate($hash, 'lastError', $err, 1);
    return;
  }

  my $json = eval { decode_json($data) };
  if ($@ || ref($json) ne 'HASH' || !$json->{access_token}) {
    my $msg = MatrixBridge__json_error($data) || 'login failed: malformed response';
    readingsSingleUpdate($hash, 'state', 'login_failed', 1);
    readingsSingleUpdate($hash, 'lastError', $msg, 1);
    return;
  }

  $hash->{helper}{access_token} = $json->{access_token};
  MatrixBridge__store_token($hash, $json->{access_token});
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, 'state', 'ready');
  readingsBulkUpdate($hash, 'user_id', $json->{user_id} // '');
  readingsBulkUpdate($hash, 'device_id', $json->{device_id} // '');
  readingsBulkUpdate($hash, 'lastError', '-');
  readingsEndUpdate($hash, 1);
  return;
}

sub MatrixBridge_UploadCallback($$$) {
  my ($param, $err, $data, $ctx) = @_;
  my $hash = $param->{hash};

  if ($err) {
    readingsSingleUpdate($hash, 'state', 'upload_failed', 1);
    readingsSingleUpdate($hash, 'lastError', $err, 1);
    return;
  }

  my $json = eval { decode_json($data) };
  if ($@ || ref($json) ne 'HASH' || !$json->{content_uri}) {
    my $msg = MatrixBridge__json_error($data) || 'upload failed: malformed response';
    readingsSingleUpdate($hash, 'state', 'upload_failed', 1);
    readingsSingleUpdate($hash, 'lastError', $msg, 1);
    return;
  }

  my $txn = time() . '-' . int(rand(1000000));
  my $token = $hash->{helper}{access_token} || MatrixBridge__load_token($hash);
  my $url  = AttrVal($hash->{NAME}, 'matrixBaseUrl', '') . '/_matrix/client/v3/rooms/' . MatrixBridge__urlencode($ctx->{room}) . '/send/m.room.message/' . $txn . '?access_token=' . MatrixBridge__urlencode($token);
  my $body = encode_json({
    msgtype => 'm.image',
    body => $ctx->{display_body},
    filename => $ctx->{filename},
    url => $json->{content_uri},
    info => {
      mimetype => $ctx->{mime},
      size => $ctx->{size},
    },
  });

  MatrixBridge_HttpNonblocking($hash,
    {
      url => $url,
      method => 'PUT',
      header => 'Content-Type: application/json',
      data => $body,
      timeout => 30,
      ignoreTLS => AttrVal($hash->{NAME}, 'disableTLSCheck', 0),
      callbackName => 'send-image',
    },
    \&MatrixBridge_SendCallback,
    {
      target => $ctx->{target},
      room => $ctx->{room},
      body => $ctx->{display_body},
      msgtype => 'm.image',
    }
  );
  return;
}

sub MatrixBridge_SendCallback($$$) {
  my ($param, $err, $data, $ctx) = @_;
  my $hash = $param->{hash};

  if ($err) {
    readingsSingleUpdate($hash, 'state', 'send_failed', 1);
    readingsSingleUpdate($hash, 'lastError', $err, 1);
    return;
  }

  my $json = eval { decode_json($data) };
  if ($@ || ref($json) ne 'HASH' || !$json->{event_id}) {
    my $msg = MatrixBridge__json_error($data) || 'send failed: malformed response';
    readingsSingleUpdate($hash, 'state', 'send_failed', 1);
    readingsSingleUpdate($hash, 'lastError', $msg, 1);
    return;
  }

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, 'state', 'ready');
  readingsBulkUpdate($hash, 'lastEventId', $json->{event_id});
  readingsBulkUpdate($hash, 'lastTarget', $ctx->{target});
  readingsBulkUpdate($hash, 'lastRoom', $ctx->{room});
  readingsBulkUpdate($hash, 'lastResult', $ctx->{body});
  readingsBulkUpdate($hash, 'lastError', '-');
  readingsEndUpdate($hash, 1);
  return;
}

sub MatrixBridge__room_for_target($$) {
  my ($hash, $target) = @_;
  return $target if $target =~ /^!/;

  my $map = AttrVal($hash->{NAME}, 'roomMap', '');
  return undef if !$map;

  foreach my $pair (split(/\s*,\s*/, $map)) {
    next if !$pair;
    my ($k, $v) = split(/\s*=\s*/, $pair, 2);
    return $v if defined $k && defined $v && $k eq $target;
  }

  my $default = AttrVal($hash->{NAME}, 'defaultTarget', '');
  return MatrixBridge__room_for_target($hash, $default) if $default && $target eq '-';
  return undef;
}

sub MatrixBridge__json_error($) {
  my ($data) = @_;
  my $json = eval { decode_json($data) };
  return undef if $@ || ref($json) ne 'HASH';
  return $json->{error} || $json->{errcode} || undef;
}

sub MatrixBridge__token_file($) {
  my ($hash) = @_;
  my $attr = AttrVal($hash->{NAME}, 'tokenFile', '');
  return $attr if $attr;
  my $modpath = AttrVal('global', 'modpath', './');
  return $modpath . '/log/' . $hash->{NAME} . '.token';
}

sub MatrixBridge__store_token($$) {
  my ($hash, $token) = @_;
  my $file = MatrixBridge__token_file($hash);
  if (open(my $fh, '>', $file)) {
    print $fh $token;
    close($fh);
  }
}

sub MatrixBridge__load_token($) {
  my ($hash) = @_;
  my $file = MatrixBridge__token_file($hash);
  return undef if !-e $file;
  open(my $fh, '<', $file) or return undef;
  local $/ = undef;
  my $token = <$fh>;
  close($fh);
  $token =~ s/\s+$// if defined $token;
  return $token;
}

sub MatrixBridge__urlencode($) {
  my ($text) = @_;
  $text =~ s/([^A-Za-z0-9\-_.~])/sprintf('%%%02X', ord($1))/seg;
  return $text;
}

sub MatrixBridge__write_temp_file($$$) {
  my ($hash, $data, $ext) = @_;
  my $tmp = '/tmp/' . $hash->{NAME} . '-' . int(gettimeofday()*1000) . '.' . $ext;
  if (open(my $fh, '>', $tmp)) {
    binmode($fh);
    print $fh $data;
    close($fh);
    return $tmp;
  }
  return undef;
}

sub MatrixBridge__content_type_for($) {
  my ($file) = @_;
  return 'image/png' if $file =~ /\.png$/i;
  return 'image/jpeg' if $file =~ /\.jpe?g$/i;
  return 'image/gif' if $file =~ /\.gif$/i;
  return 'application/octet-stream';
}

1;
