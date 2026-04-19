module xml_state_machine;
import state_machine;
import std::io;

$exec("parser.c3", { "state", "yxml.c3.in" });

fn int main(String[] args) {
  io::printfn("%s", YxmlState.names);
	return 0;
}
