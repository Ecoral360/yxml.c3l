module xml_state_machine::utils;

macro @starts_with(String $s, String $needle) {
  $if !$defined($s[$needle.len - 1]):
    return false;
  $endif

  $foreach $i, $c : $needle:
    $if $defined($s[$i]) &&& $s[$i] != $c:
      return false;
    $endif
  $endforeach
  return true;
}

macro @trim_start(String $s) {
  $foreach $i, $c : $s:
    $if $s[$i] != ' ':
      return $s[$i..];
    $endif
  $endforeach
}

macro @trim_end(String $s) {
  $if $s == " ":
    return "";
  $endif

  $for var $i = $s.len - 1; $i > 0; $i-- :
    $if $s[$i] != ' ':
      return $s[..$i];
    $endif
  $endfor
}

macro @trim(String $s) {
  return @trim_end(@trim_start($s));
}

macro @split_val(String $s) {
  $for var $i = 0; $i < $s.len; $i++ :
    $if $s[$i] == ';':
      return @trim_start($s[$i+1..]);
    $endif
  $endfor
  return @trim($s);
}
