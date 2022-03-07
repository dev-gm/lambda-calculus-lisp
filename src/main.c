#include <error_handling.h>
#include <parser.h>

struct parser_list *parsed_list;

int main(int argc, char **argv) {
	const char *filename;
	exit_if(argc != 2, 1, "Too many or too few arguments");
	filename = argv[1];
	parsed_list = parse_file(filename);
}
