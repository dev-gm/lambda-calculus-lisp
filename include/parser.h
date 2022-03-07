#ifndef PARSER_H

#define PARSER_H

#include <stdlib.h>

struct parser_list {
	struct parser_list_item {
		union {
			char *atom;
			struct parser_list *list;
		} item;
		enum {
			ATOM,
			LIST,
		} type: 2;
	} *items;
	size_t items_len;
};

struct parser_list *parse_file(const char *filename);

#endif
