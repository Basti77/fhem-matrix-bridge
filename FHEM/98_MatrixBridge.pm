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
sub MatrixBridge_SyncStart($);
sub MatrixBridge_SyncPoll($);
sub MatrixBridge_SyncCallback($$$);
sub MatrixBridge_ProcessMessage($$$$);
sub MatrixBridge_CmdList($$);
sub MatrixBridge_CmdDevice($$$);
sub MatrixBridge_CmdRaw($$$);
sub MatrixBridge__room_for_target($$);
sub MatrixBridge__json_error($);
sub MatrixBridge__store_token($$);
sub MatrixBridge__load_token($);
sub MatrixBridge__token_file($);
sub MatrixBridge__store_since($$);
sub MatrixBridge__load_since($);
sub MatrixBridge__since_file($);
sub MatrixBridge__urlencode($);
sub MatrixBridge__write_temp_file($$$);
sub MatrixBridge__content_type_for($);

sub MatrixBridge_Initialize($) {
  my ($hash) = @_;
  $hash->{DefFn}    = 'MatrixBridge_Define';
  $hash->{UndefFn}  = 'MatrixBridge_Undef';
  $hash->{SetFn}    = 'MatrixBridge_Set';
  $hash->{AttrFn}   = 'MatrixBridge_Attr';
  $hash->{AttrList} = 'matrixBaseUrl matrixUser matrixPassword roomMap defaultTarget tokenFile autoLogin:0,1 disableTLSCheck:0,1 verbose:0,1 botKeyword allowedUsers exposeRoom allowRawCmds:0,1 syncEnabled:0,1 syncInterval';
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
  $hash->{helper}{sync_active} = 0;
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

  elsif ($cmd eq 'startSync') {
    MatrixBridge_SyncStart($hash);
    return undef;
  }
  elsif ($cmd eq 'stopSync') {
    $hash->{helper}{sync_active} = 0;
    RemoveInternalTimer($hash, 'MatrixBridge_SyncPoll');
    readingsSingleUpdate($hash, 'syncState', 'stopped', 1);
    return undef;
  }

  return 'Unknown argument ' . $cmd . ', choose one of login:noArg logout:noArg send sendNotice sendImage sendPlot startSync:noArg stopSync:noArg';
}

sub MatrixBridge_Attr(@) {
  my ($cmd, $name, $attrName, $attrValue) = @_;
  my $hash = $defs{$name};

  if ($cmd eq 'set' && $attrName eq 'autoLogin' && $attrValue) {
    MatrixBridge_Login($hash, 1);
  }
  if ($cmd eq 'set' && $attrName eq 'syncEnabled' && $attrValue) {
    MatrixBridge_SyncStart($hash);
  }
  if ($cmd eq 'set' && $attrName eq 'syncEnabled' && !$attrValue) {
    $hash->{helper}{sync_active} = 0;
    RemoveInternalTimer($hash, 'MatrixBridge_SyncPoll');
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

  # Extract image dimensions from PNG header (bytes 16-23)
  my ($img_w, $img_h);
  if (length($data) >= 24 && substr($data, 0, 4) eq "\x89PNG") {
    ($img_w, $img_h) = unpack('NN', substr($data, 16, 8));
  }

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
      img_w => $img_w,
      img_h => $img_h,
    }
  );
  return undef;
}

sub MatrixBridge_SendPlot($$$$) {
  my ($hash, $target, $plot, $caption) = @_;
  my $name = $hash->{NAME};

  my $png_file;

  # Try SVG-based conversion via rsvg-convert for best text rendering
  if ($defs{$plot} && $defs{$plot}{TYPE} eq 'SVG') {
    $png_file = eval { MatrixBridge__svg_to_png($hash, $plot) };
    if ($@) {
      Log3 $name, 3, "MatrixBridge ($name): SVG conversion failed: $@";
      $png_file = undef;
    }
  }

  # Fallback: Signalbot_getPNG or plotAsPng
  if (!$png_file || !-f ($png_file // '')) {
    if (defined &Signalbot_getPNG) {
      $png_file = eval { Signalbot_getPNG($hash, $plot) };
    } else {
      my $png = eval { plotAsPng($plot) };
      return 'plotAsPng failed for ' . $plot if !$png;
      return $png if $png =~ /^Error:/;
      $png_file = MatrixBridge__write_temp_file($hash, $png, 'png');
    }
  }

  return 'Could not create plot PNG for ' . $plot if !$png_file || !-f $png_file;
  return MatrixBridge_SendImage($hash, $target, $png_file, $caption, 'image/png');
}

sub MatrixBridge__svg_to_png($$) {
  my ($hash, $plot) = @_;
  my $name = $hash->{NAME};

  # Check that rsvg-convert is available
  my $rsvg = `which rsvg-convert 2>/dev/null`;
  chomp $rsvg;
  if (!$rsvg) {
    Log3 $name, 4, "MatrixBridge ($name): rsvg-convert not found, skipping SVG conversion";
    return undef;
  }

  # Use FHEM's SVG rendering to get SVG data (same approach as plotAsPng)
  return undef if !defined($defs{$plot});

  my $devspec = 'TYPE=FHEMWEB';
  my $port = AttrVal($plot, 'plotAsPngPort', undef);
  $devspec .= ":FILTER=i:PORT=$port" if defined($port);
  my @webs = devspec2array($devspec);
  foreach (@webs) {
    if (!InternalVal($_, 'TEMPORARY', undef)) {
      $FW_wname = InternalVal($_, 'NAME', '');
      last;
    }
  }
  return undef if !$FW_wname;

  $FW_RET = '';
  $FW_webArgs{dev} = $plot;
  $FW_webArgs{logdev} = InternalVal($plot, 'LOGDEVICE', '');
  $FW_webArgs{gplotfile} = InternalVal($plot, 'GPLOTFILE', '');
  $FW_webArgs{logfile} = InternalVal($plot, 'LOGFILE', 'CURRENT');
  $FW_pos{zoom} = $FW_pos{zoom} // '';
  $FW_pos{off} = $FW_pos{off} // '';

  eval { SVG_showLog("$plot/SVG") };
  my $svg_data = $FW_RET;
  $FW_RET = '';

  if (!$svg_data || $svg_data !~ /<svg/i) {
    Log3 $name, 4, "MatrixBridge ($name): could not get SVG data for $plot";
    return undef;
  }

  # Increase plot height for better label visibility (match plotsize or use larger default)
  my ($w, $h) = split(',', AttrVal($plot, 'plotsize', '800,400'));
  $h = 400 if $h < 400;

  # Ensure viewBox is set for proper scaling
  if ($svg_data =~ /width='(\d+)px'\s+height='(\d+)px'/) {
    my ($svg_w, $svg_h) = ($1, $2);
    if ($svg_data !~ /viewBox/) {
      $svg_data =~ s/(width='${svg_w}px'\s+height='${svg_h}px')/$1 viewBox="0 0 $svg_w $svg_h"/;
    }
  }

  # Write SVG to temp file
  my $svg_file = MatrixBridge__write_temp_file($hash, $svg_data, 'svg');
  return undef if !$svg_file;

  # Convert SVG to PNG using rsvg-convert
  my $png_file = $svg_file;
  $png_file =~ s/\.svg$/.png/;

  my $ret = system("$rsvg -f png -w $w -h $h -a -o '$png_file' '$svg_file' 2>/dev/null");
  unlink($svg_file);

  if ($ret != 0 || !-f $png_file) {
    Log3 $name, 3, "MatrixBridge ($name): rsvg-convert failed (exit $ret)";
    return undef;
  }

  Log3 $name, 4, "MatrixBridge ($name): SVG plot converted via rsvg-convert: $png_file";
  return $png_file;
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
  $hash->{helper}{my_user_id} = $json->{user_id} // '';
  MatrixBridge__store_token($hash, $json->{access_token});
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, 'state', 'ready');
  readingsBulkUpdate($hash, 'user_id', $json->{user_id} // '');
  readingsBulkUpdate($hash, 'device_id', $json->{device_id} // '');
  readingsBulkUpdate($hash, 'lastError', '-');
  readingsEndUpdate($hash, 1);

  if (AttrVal($name, 'syncEnabled', 0)) {
    MatrixBridge_SyncStart($hash);
  }
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
  my %img_info = (
    mimetype => $ctx->{mime},
    size => $ctx->{size},
  );
  $img_info{w} = $ctx->{img_w} if $ctx->{img_w};
  $img_info{h} = $ctx->{img_h} if $ctx->{img_h};

  my $body = encode_json({
    msgtype => 'm.image',
    body => $ctx->{display_body},
    filename => $ctx->{filename},
    url => $json->{content_uri},
    info => \%img_info,
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

# ---------------------------------------------------------------------------
# Inbound: /sync Long-Polling
# ---------------------------------------------------------------------------

sub MatrixBridge_SyncStart($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $token = $hash->{helper}{access_token} || MatrixBridge__load_token($hash);
  if (!$token) {
    Log3 $name, 3, "MatrixBridge ($name): cannot start sync - no access token";
    return;
  }
  $hash->{helper}{access_token} = $token;
  $hash->{helper}{sync_active} = 1;

  my $since = MatrixBridge__load_since($hash);
  $hash->{helper}{sync_since} = $since if $since;

  readingsSingleUpdate($hash, 'syncState', 'running', 1);
  MatrixBridge_SyncPoll($hash);
}

sub MatrixBridge_SyncPoll($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if !$hash->{helper}{sync_active};

  my $base  = AttrVal($name, 'matrixBaseUrl', '');
  my $token = $hash->{helper}{access_token};
  return if !$base || !$token;

  my $timeout = 30;
  my $url = $base . '/_matrix/client/v3/sync?timeout=' . ($timeout * 1000)
          . '&access_token=' . MatrixBridge__urlencode($token);

  if ($hash->{helper}{sync_since}) {
    $url .= '&since=' . MatrixBridge__urlencode($hash->{helper}{sync_since});
  }

  MatrixBridge_HttpNonblocking($hash,
    {
      url => $url,
      method => 'GET',
      timeout => $timeout + 15,
      ignoreTLS => AttrVal($name, 'disableTLSCheck', 0),
      callbackName => 'sync',
    },
    \&MatrixBridge_SyncCallback,
    {}
  );
}

sub MatrixBridge_SyncCallback($$$) {
  my ($param, $err, $data, $ctx) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if (!$hash->{helper}{sync_active}) {
    return;
  }

  if ($err) {
    Log3 $name, 3, "MatrixBridge ($name): sync error: $err";
    readingsSingleUpdate($hash, 'syncState', 'error', 1);
    readingsSingleUpdate($hash, 'lastError', "sync: $err", 1);
    # Retry after interval
    my $interval = AttrVal($name, 'syncInterval', 5);
    InternalTimer(gettimeofday() + $interval, 'MatrixBridge_SyncPoll', $hash, 0);
    return;
  }

  my $json = eval { decode_json($data) };
  if ($@ || ref($json) ne 'HASH') {
    Log3 $name, 3, "MatrixBridge ($name): sync: malformed response";
    my $interval = AttrVal($name, 'syncInterval', 5);
    InternalTimer(gettimeofday() + $interval, 'MatrixBridge_SyncPoll', $hash, 0);
    return;
  }

  # Store next_batch as since token
  if ($json->{next_batch}) {
    $hash->{helper}{sync_since} = $json->{next_batch};
    MatrixBridge__store_since($hash, $json->{next_batch});
  }

  readingsSingleUpdate($hash, 'syncState', 'running', 1);

  # Process room events
  my $rooms = $json->{rooms}{join} // {};
  my $my_user = $hash->{helper}{my_user_id} // '';

  foreach my $room_id (keys %$rooms) {
    my $timeline = $rooms->{$room_id}{timeline}{events} // [];
    foreach my $event (@$timeline) {
      next if !$event->{type} || $event->{type} ne 'm.room.message';
      next if !$event->{content} || !$event->{sender};

      # Skip own messages
      next if $my_user && $event->{sender} eq $my_user;

      my $sender  = $event->{sender};
      my $body    = $event->{content}{body} // '';
      my $msgtype = $event->{content}{msgtype} // '';

      next if $msgtype ne 'm.text';
      next if !$body;

      MatrixBridge_ProcessMessage($hash, $room_id, $sender, $body);
    }
  }

  # Immediately poll again (long-polling)
  MatrixBridge_SyncPoll($hash);
}

# ---------------------------------------------------------------------------
# Inbound: Message Processing
# ---------------------------------------------------------------------------

sub MatrixBridge_ProcessMessage($$$$) {
  my ($hash, $room_id, $sender, $body) = @_;
  my $name = $hash->{NAME};

  # Check botKeyword
  my $keyword = AttrVal($name, 'botKeyword', '');
  if ($keyword) {
    if ($body !~ /^\s*\Q$keyword\E\s+(.*)$/si) {
      return;  # Message doesn't start with keyword
    }
    $body = $1;  # Strip keyword prefix
  }

  # Check allowedUsers
  my $allowed = AttrVal($name, 'allowedUsers', '');
  if ($allowed) {
    my %users = map { $_ => 1 } split(/\s*,\s*/, $allowed);
    if (!$users{$sender}) {
      Log3 $name, 4, "MatrixBridge ($name): ignoring message from unauthorized user: $sender";
      return;
    }
  }

  # Update readings for inbound message
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, 'lastInboundSender', $sender);
  readingsBulkUpdate($hash, 'lastInboundRoom', $room_id);
  readingsBulkUpdate($hash, 'lastInboundMessage', $body);
  readingsEndUpdate($hash, 1);

  Log3 $name, 4, "MatrixBridge ($name): inbound from $sender: $body";

  # Parse command
  $body =~ s/^\s+|\s+$//g;

  if ($body =~ /^list$/i) {
    MatrixBridge_CmdList($hash, $room_id);
    return;
  }

  if ($body =~ /^cmd\s+(.+)$/si) {
    MatrixBridge_CmdRaw($hash, $room_id, $1);
    return;
  }

  # Device control: <alias> <command> [<args>]
  if ($body =~ /^(\S+)\s+(.+)$/s) {
    MatrixBridge_CmdDevice($hash, $room_id, $body);
    return;
  }

  # Unknown command
  my $reply = "Unbekannter Befehl: $body\nVerfügbar: list, <Gerät> <Befehl>";
  my $raw = AttrVal($name, 'allowRawCmds', 0);
  $reply .= ', cmd <FHEM-Befehl>' if $raw;
  MatrixBridge_Send($hash, $room_id, $reply, 'm.notice');
}

# ---------------------------------------------------------------------------
# Inbound: Command Handlers
# ---------------------------------------------------------------------------

sub MatrixBridge_CmdList($$) {
  my ($hash, $room_id) = @_;
  my $name = $hash->{NAME};

  my $expose_room = AttrVal($name, 'exposeRoom', '');
  if (!$expose_room) {
    MatrixBridge_Send($hash, $room_id, "Kein exposeRoom konfiguriert.", 'm.notice');
    return;
  }

  my @lines;
  foreach my $devname (sort keys %defs) {
    my $dhash = $defs{$devname};
    next if !$dhash;

    my $rooms_attr = AttrVal($devname, 'room', '');
    my @dev_rooms = split(/\s*,\s*/, $rooms_attr);
    next if !grep { $_ eq $expose_room } @dev_rooms;

    my $alias = AttrVal($devname, 'alias', $devname);
    my $state = ReadingsVal($devname, 'state', '?');
    push @lines, "$alias ($state)";
  }

  if (!@lines) {
    MatrixBridge_Send($hash, $room_id, "Keine Geräte im Raum '$expose_room' gefunden.", 'm.notice');
    return;
  }

  my $reply = "Steuerbare Geräte:\n" . join("\n", @lines);
  MatrixBridge_Send($hash, $room_id, $reply, 'm.notice');
}

sub MatrixBridge_CmdDevice($$$) {
  my ($hash, $room_id, $body) = @_;
  my $name = $hash->{NAME};

  my $expose_room = AttrVal($name, 'exposeRoom', '');
  if (!$expose_room) {
    MatrixBridge_Send($hash, $room_id, "Kein exposeRoom konfiguriert.", 'm.notice');
    return;
  }

  # Parse: <device_alias> <command> [<args>]
  my ($dev_input, $cmd_rest) = $body =~ /^(\S+)\s+(.+)$/s;
  if (!$dev_input || !$cmd_rest) {
    MatrixBridge_Send($hash, $room_id, "Syntax: <Gerät> <Befehl> [Parameter]", 'm.notice');
    return;
  }

  # Find device by alias or name in exposeRoom
  my $target_dev;
  foreach my $devname (keys %defs) {
    my $dhash = $defs{$devname};
    next if !$dhash;

    my $rooms_attr = AttrVal($devname, 'room', '');
    my @dev_rooms = split(/\s*,\s*/, $rooms_attr);
    next if !grep { $_ eq $expose_room } @dev_rooms;

    my $alias = AttrVal($devname, 'alias', '');
    if (lc($alias) eq lc($dev_input) || lc($devname) eq lc($dev_input)) {
      $target_dev = $devname;
      last;
    }
  }

  if (!$target_dev) {
    MatrixBridge_Send($hash, $room_id, "Gerät '$dev_input' nicht gefunden im Raum '$expose_room'.", 'm.notice');
    return;
  }

  my $fhem_cmd = "set $target_dev $cmd_rest";
  Log3 $name, 3, "MatrixBridge ($name): executing: $fhem_cmd";
  my $result = eval { fhem($fhem_cmd, 1) };

  if ($@) {
    MatrixBridge_Send($hash, $room_id, "Fehler: $@", 'm.notice');
    return;
  }

  my $alias = AttrVal($target_dev, 'alias', $target_dev);
  my $reply = defined($result) && $result ne '' ? "$alias: $result" : "$alias: OK";
  MatrixBridge_Send($hash, $room_id, $reply, 'm.notice');
}

sub MatrixBridge_CmdRaw($$$) {
  my ($hash, $room_id, $cmd) = @_;
  my $name = $hash->{NAME};

  if (!AttrVal($name, 'allowRawCmds', 0)) {
    MatrixBridge_Send($hash, $room_id, "Raw-Befehle sind nicht aktiviert (allowRawCmds).", 'm.notice');
    return;
  }

  Log3 $name, 3, "MatrixBridge ($name): raw cmd: $cmd";
  my $result = eval { fhem($cmd, 1) };

  if ($@) {
    MatrixBridge_Send($hash, $room_id, "Fehler: $@", 'm.notice');
    return;
  }

  my $reply = defined($result) && $result ne '' ? $result : 'OK';
  MatrixBridge_Send($hash, $room_id, $reply, 'm.notice');
}

# ---------------------------------------------------------------------------
# Since-Token Persistence
# ---------------------------------------------------------------------------

sub MatrixBridge__since_file($) {
  my ($hash) = @_;
  my $modpath = AttrVal('global', 'modpath', './');
  return $modpath . '/log/' . $hash->{NAME} . '.since';
}

sub MatrixBridge__store_since($$) {
  my ($hash, $since) = @_;
  my $file = MatrixBridge__since_file($hash);
  if (open(my $fh, '>', $file)) {
    print $fh $since;
    close($fh);
  }
}

sub MatrixBridge__load_since($) {
  my ($hash) = @_;
  my $file = MatrixBridge__since_file($hash);
  return undef if !-e $file;
  open(my $fh, '<', $file) or return undef;
  local $/ = undef;
  my $since = <$fh>;
  close($fh);
  $since =~ s/\s+$// if defined $since;
  return $since;
}

1;
