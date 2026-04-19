import std::io;
import std::io::file;
import std::collections::map;
import std::collections::list;

HashMap{String, String} states;

fn String condtoc(String cond) {
  cond = cond.trim();

  switch {
    case cond[0] == '$':
      return string::tformat("x.%s = ch", cond[1..]);
    case cond[0] == '\'':
      return string::tjoin(cond.tsplit("|"), " || ");

    case array::@all(cond, fn(c,a) => ascii::is_alpha(c) || ascii::is_digit(c) || c == '_'):
      return string::tformat("yxml_is%s(ch)", cond);
  }

  abort("Unkown condition: %s", cond);
}

fn String[] acttoc(String *next, String[] act) {
  String r;
  List{String} c;

  foreach (part : act) {
    part = part.trim();
    switch {
      case part[0] == '$':
        c.push(string::tformat("x.%s = ch;", part[1..]));
      case part[0] == '@':
        c.push(string::tformat("x.nextstate = YXMLS_%s;", part[1..].to_upper_copy(tmem)));
      case part[0] == '"':
        c.push(string::tformat("x.nextstate = YXMLS_%s;", next.to_upper_copy(tmem)));
        c.push(string::tformat("x.string = %s;", part));
        *next = "string";

      case array::@all(part, fn(c,a) => ascii::is_alpha(c) || ascii::is_digit(c) || c == '_'):
        if (r != "") abort(string::tformat("Only one function please '%s' !", act));
        r = string::tformat("yxml_%s(x, ch)", part);
    }
  }

  c.push(string::tformat("return %s;", r == "" ? "YXML_OK" : r));

  return c.to_array(tmem);
}

fn String gen_code(String state, String[] descs) {
  List{String} code;
  code.push(string::tformat("case YxmlState.YXMLS_%s:", state.to_upper_copy(tmem)));

  foreach (desc : descs) {
    desc = desc.trim();
    String[] parts = desc.tsplit(" ");

    String cond = parts[0];
    cond = condtoc(cond);

    String next = parts[^1];
    String[] act = parts.len > 1 ? parts[1..^2] : {};
    act = acttoc(&next, act);

    code.push(string::tformat("\tif (%s) {", cond));

    switch {
      case next == "@":
        code.push("\t\tx.state = x.nextstate;");
      case next != state:
        code.push(string::tformat("\t\tx.state = YXMLS_%s;", next.to_upper_copy(tmem)));
    }

    foreach (line : act) {
      code.push(string::tformat("\t\t%s", line));
    }

    code.push("}");

  }

  return string::tjoin(code.to_array(tmem), "\n");
}

fn void read_machine(InStream state_stream) {
  while (try String line = io::treadline(state_stream)) {
    line = line.trim();
    if (line.len == 0 || line[0] == '#') continue;
    String[] line1 = line.tsplit(" ", 2);
    String[] splits = line1[1].tsplit(";");
    foreach (&state : splits) {
      *state = state.trim();
    }
    String state = line1[0];
    state = state.trim();
    String[] desc = splits[1..];
    if (try states[state]) {
      abort(string::tformat("State '%s' specified more than once.", state));
    }
    states[state] = gen_code(state, desc);
  }
}


fn void main(String[] args) {
  states.init(tmem);

  String state_file_path = args[1];

  File state_file = file::open(string::tformat("../%s", state_file_path), "r")!!;
  read_machine(&state_file);

  String in_file_path = args[2];
  String in_file_code = (String) file::load(tmem, string::tformat("../%s", in_file_path))!!;

  DString s_states;
  foreach (state_key : states.keys(tmem)) {
    s_states.append("YXMLS_");
    s_states.append(state_key.to_upper_copy(tmem));
    s_states.append(",\n");
  }
  in_file_code = in_file_code.treplace("/*=STATES=*/", s_states.str_view());
  in_file_code = in_file_code.treplace("/*=SWITCH=*/", string::tjoin(states.values(tmem), ";\n"));

  File outfile = file::open("out.c3", "w")!!;
  (void)outfile.write((char[]) in_file_code);

  io::print(in_file_code);
}
