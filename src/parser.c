#include <error_handling.h>
#include <parser.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#define is_special_char(CH) (CH==';'||CH=='"'||CH=='('||CH==')'||CH=='\\'||CH==' '||CH=='\n')

static void debug_print_list(const char *prepend, struct parser_list *list) {
	for (size_t i = 0; i < list->items_len; ++i) {
		switch (list->items[i].type) {
			case ATOM: {
				fprintf(stderr, "%s<ATOM>%s</ATOM>\n", prepend, list->items[i].item.atom);
				break;
			}
			case LIST: {
				fprintf(stderr, "%s<LIST>\n", prepend);
				char temp_prepend[strlen(prepend) + 1];
				strcpy(temp_prepend, prepend);
				strcpy(temp_prepend + strlen(prepend), "\t");
				debug_print_list(temp_prepend, list->items[i].item.list);
				fprintf(stderr, "%s</LIST>\n", prepend);
				break;
			}
		}
	}
}

static struct parser_list *new_list(size_t items_len) {
	struct parser_list *out = malloc(sizeof(struct parser_list));
	out->items = malloc(items_len * sizeof(struct parser_list_item));
	out->items_len = items_len;
	return out;
}

static void add_text_to_list(struct parser_list *list, size_t *index, char **start, char *end) {
	char **dest = &list->items[*index].item.atom;
	size_t text_len = end - *start,
		   skipped = 0;
	bool skipped_last = false;
	list->items[*index].type = ATOM;
	*dest = malloc(text_len + 1);
	for (size_t i = 0; i < text_len; ++i) {
		if ((*start)[i] == '\\' && !skipped_last) {
			++skipped;
			skipped_last = true;
			continue;
		}
		(*dest)[i-skipped] = (*start)[i];
		skipped_last = false;
	}
	(*dest)[text_len-skipped] = '\0';
	++(*index);
	*start = NULL;
}

// (fn (arg0 (fn arg0 arg1 (fn arg0))) arg1 (fn arg0))
// ptr starts 1 char after left paren. when returns, ptr is at matching right paren
static inline struct parser_list *parse_string(char **ptr) {
	char *string = *ptr,
		 *segment_start = NULL;
	size_t i,
		   string_len = strlen(string),
		   items_len = 0,
		   index = 0;
	bool comment_mode = false,
		 string_mode = false;
	struct parser_list *list;
	{
		int paren_depth = 0;
		for (i = 0; i < string_len; ++i) {
			if (string[i] == '\\') {
				++i;
				continue;
			} else if (comment_mode) {
				if (string[i] == ';')
					comment_mode = false;
				continue;
			} else if (string_mode) {
				if (string[i] == '"') {
					if (paren_depth == 0)
						++items_len;
					string_mode = false;
				}
				continue;
			}
			// if char before was not special and char here is special (e.g. 'e)', 'e ', 'e;')
			if (paren_depth == 0 && i != 0 && (!is_special_char(string[i-1]) || string[i-1] == '\\') && is_special_char(string[i]))
				++items_len;
			switch (string[i]) {
				case ';':
					comment_mode = true;
					break;
				case '(':
					++paren_depth;
					break;
				case ')':
					switch (--paren_depth) {
						case -1:
							goto count_loop_end;
							break;
						case 0:
							++items_len;
							break;
					}
					break;
				case '"':
					string_mode = true;
					break;
			}
		}
	}
count_loop_end: list = new_list(items_len);
	comment_mode = false;
	string_mode = false;
	if (!is_special_char(string[0]))
		segment_start = string;
	for (i = 0; i < string_len; ++i) {
		if (string[i] == '\\') {
			++i;
			continue;
		} else if (comment_mode) {
			if (string[i] == ';')
				comment_mode = false;
			continue;
		} else if (string_mode) {
			if (string[i] == '"') {
				add_text_to_list(list, &index, &segment_start, string + i);
				string_mode = false;
			}
			continue;
		}
		switch (string[i]) {
			case ';':
				comment_mode = true;
				break;
			case '(':
				exit_if(i+1 == string_len, 1, "Unmatched '(' near string %.10s", string + i);
				*ptr = string + i + 1;
				struct parser_list *temp_list = parse_string(ptr);
				exit_if(*(*ptr+1) == '\0', 1, "Unmatched '(' near string %.10s", *ptr);
				++*ptr;
				i = *ptr - string - 1;
				list->items[index].type = LIST;
				list->items[index].item.list = temp_list;
				++index;
				break;
			case ')':
				if (segment_start)
					add_text_to_list(list, &index, &segment_start, string + i);
				*ptr = string + i;
				return list;
			case '"':
				segment_start = string + i + 1;
				string_mode = true;
				break;
			case ' ':
				if (segment_start == NULL) {
					while (string[i] == ' ')
						++i;
					if (is_special_char(string[i]))
						--i;
					else
						segment_start = string + i;
				} else {
					add_text_to_list(list, &index, &segment_start, string + i);
					--i;
				}
				break;
		}
	}
	exit_if(true, 1, "Unmatched '(' near string %.10s", string + i);
}

struct parser_list *parse_file(const char *filename) {
	struct parser_list *out;
	FILE *file;
	size_t file_len;
	char *file_contents;
	exit_if_null(file = fopen(filename, "r"), 1, "Failed to open file (%s) for reading", filename);
	exit_if_nonzero(fseek(file, 0, SEEK_END), 1, "Failed to seek to end of file (%s)", filename);
	file_len = ftell(file);
	exit_if_nonzero(fseek(file, 0, SEEK_SET), 1, "Failed to seek to start of file (%s)", filename);
	file_contents = malloc(file_len + 1);
	fgets(file_contents, file_len, file);
	file_contents[file_len] = '\0';
	{
		bool comments_mode = false;
		size_t i = 0;
		while (i < file_len && (file_contents[i] == ' ' || file_contents[i] == '\n' || file_contents[i] == '\t' || comments_mode)) {
			if (file_contents[i] == ';')
				comments_mode = !comments_mode;
			else
				++file_contents;
			++i;
		}
		exit_if(i == file_len, 1, "File (%s) is empty", filename);
		exit_if(file_contents[i] != '(', 1, "Atoms not in lists are not permitted, near string:\n%.10s)", file_contents + i);
		file_contents += i + 1;
		file_len -= i;
	}
	out = parse_string(&file_contents);
	//debug_print_list("", out);
	fclose(file);
	return out;
}
