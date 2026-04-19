<*
 Yxml in c3 (https://dev.yorhel.nl/yxml), by Manu Linares

 (https://code.blicky.net/yorhel/yxml/src/branch/master/yxml.c)
 (https://code.blicky.net/yorhel/yxml/src/branch/master/yxml.h)

 I did my best to do a mostly one to one translation of the yxml C source to C3.
*>
// module std::encoding::xml::internal @private;

constdef Ret
{
	EEOF        = -5, 	/* Unexpected EOF                             */
	EREF        = -4,	/* Invalid character or entity reference (&whatever;) */
	ECLOSE      = -3,	/* Close tag does not match open tag (<Tag> .. </OtherTag>) */
	ESTACK      = -2,	/* Stack overflow (too deeply nested tags or too long element/attribute name) */
	ESYN        = -1,	/* Syntax error (unexpected byte)             */
	OK          =  0,	/* Character consumed, no new token present   */
	ELEMSTART   =  1,	/* Start of an element:   '<Tag ..'           */
	CONTENT     =  2,	/* Element content                            */
	ELEMEND     =  3,	/* End of an element:     '.. />' or '</Tag>' */
	ATTRSTART   =  4,	/* Attribute:             'Name=..'           */
	ATTRVAL     =  5,	/* Attribute value                            */
	ATTREND     =  6,	/* End of attribute       '.."'               */
	PISTART     =  7,	/* Start of a processing instruction          */
	PICONTENT   =  8,	/* Content of a PI                            */
	PIEND       =  9,   /* End of a processing instruction            */
}

/* When, exactly, are tokens returned?
 *
 * <TagName
 *   '>' ELEMSTART
 *   '/' ELEMSTART, '>' ELEMEND
 *   ' ' ELEMSTART
 *     '>'
 *     '/', '>' ELEMEND
 *     Attr
 *       '=' ATTRSTART
 *         "X ATTRVAL
 *           'Y'  ATTRVAL
 *             'Z'  ATTRVAL
 *               '"' ATTREND
 *                 '>'
 *                 '/', '>' ELEMEND
 *
 * </TagName
 *   '>' ELEMEND
 */

struct Parser
{
/* PUBLIC (read-only) */

	/* Name of the current element, zero-length if not in any element. Changed
	 * after YXML_ELEMSTART. The pointer will remain valid up to and including
	 * the next non-YXML_ATTR* token, the pointed-to buffer will remain valid
	 * up to and including the YXML_ELEMEND for the corresponding element. */
	char* elem;

	/* The last read character(s) of an attribute value (YXML_ATTRVAL), element
	 * data (YXML_CONTENT), or processing instruction (YXML_PICONTENT). Changed
	 * after one of the respective YXML_ values is returned, and only valid
	 * until the next yxml_parse() call. Usually, this string only consists of
	 * a single byte, but multiple bytes are returned in the following cases:
	 * - "<?SomePI ?x ?>": The two characters "?x"
	 * - "<![CDATA[ ]x ]]>": The two characters "]x"
	 * - "<![CDATA[ ]]x ]]>": The three characters "]]x"
	 * - "&#N;" and "&#xN;", where dec(n) > 127. The referenced Unicode
	 *   character is then encoded in multiple UTF-8 bytes.
	 */
	char[8] data;

	/* Name of the current attribute. Changed after YXML_ATTRSTART, valid up to
	 * and including the next YXML_ATTREND. */
	char* attr;

	/* Name/target of the current processing instruction, zero-length if not in
	 * a PI. Changed after YXML_PISTART, valid up to (but excluding)
	 * the next YXML_PIEND. */
	char* pi;

	/* Line number, byte offset within that line, and total bytes read. These
	 * values refer to the position _after_ the last byte given to
	 * yxml_parse(). These are useful for debugging and error reporting. */
	ulong byte;
	ulong total;
	uint line;


	/* PRIVATE */
	State state;
	char* stack; /* Stack of element names + attribute/PI name, separated by \0. Also starts with a \0. */
	usz stacksize, stacklen;
	uint reflen;
	uint quote;
	State nextstate; /* Used for '@' state remembering and for the "string" consuming state */
	uint ignore;
	char* string;
}

<* Returns a view of the current element name. *>
fn String Parser.elem_view(&self) @inline => ((ZString)self.elem).str_view();
<* Returns a view of the current attribute name.*>
fn String Parser.attr_view(&self) @inline => ((ZString)self.attr).str_view();
<* Returns a view of the current processing instruction name. *>
fn String Parser.pi_view(&self) @inline => ((ZString)self.pi).str_view();
<* Returns a view of the contents of the data buffer. *>
fn String Parser.data_view(&self) @inline => ((ZString)&self.data[0]).str_view();

enum State : int
{
	STRING,
  MISC2A,
ENC3,
CD1,
VER3,
COMMENT1,
MISC1,
STD0,
XMLDECL7,
XMLDECL2,
LEE2,
ETAG2,
ELEM0,
LE3,
VER0,
CD2,
DT0,
PI0,
LE1,
COMMENT3,
ELEM2,
ETAG0,
XMLDECL5,
ELEM3,
ATTR4,
DT1,
ATTR1,
XMLDECL8,
ATTR3,
CD0,
ETAG1,
STD3,
ELEM1,
DT2,
MISC2,
PI1,
XMLDECL6,
ENC1,
XMLDECL1,
XMLDECL0,
COMMENT4,
MISC3,
ENC0,
XMLDECL9,
DT3,
PI3,
LE2,
LE0,
PI4,
LEE1,
COMMENT2,
STD1,
COMMENT0,
ENC2,
ATTR0,
INIT,
DT4,
MISC0,
VER1,
XMLDECL3,
STD2,
PI2,
ATTR2,
XMLDECL4,
VER2,
LEQ0,

}

macro bool isChar(uint c) => true;
/* 0xd should be part of SP, too, but yxml_parse() already normalizes that into 0xa */
macro bool isSP(uint c)        => (c == 0x20 || c == 0x09 || c == 0x0a);
macro bool isAlpha(uint c)     => ((c|32)-'a' < 26);
macro bool isNum(uint c)       => (c-'0' < 10);
macro bool isHex(uint c)       => (isNum(c) || (c|32)-'a' < 6);
macro bool isEncName(uint c)   => (isAlpha(c) || isNum(c) || c == '.' || c == '_' || c == '-');
macro bool isNameStart(uint c) => (isAlpha(c) || c == ':' || c == '_' || c >= 128);
macro bool isName(uint c)      => (isNameStart(c) || isNum(c) || c == '-' || c == '.');
/* XXX: The valid characters are dependent on the quote char, hence the access to x->quote */
macro bool isAttValue(Parser* x, uint c) => (isChar(c) && c != x.quote && c != '<' && c != '&');
/* Anything between '&' and ';', the yxml_ref* functions will do further
 * validation. Strictly speaking, this is "yxml_isName(c) || c == '#'", but
 * this parser doesn't understand entities with '.', ':', etc, anwyay.  */
macro bool isRef(uint c) => (isNum(c) || isAlpha(c) || c == '#');

macro ulong int_from_5_chars(uint a, uint b, uint c, uint d, uint e) =>
	((((ulong)a)<<32) | (((ulong)b)<<24) | (((ulong)c)<<16) | (((ulong)d)<<8) | (ulong)e);

/* Set the given char value to ch (0<=ch<=255). */
fn void setchar(char* dest, uint ch)
{
	*dest = (char)ch;
}

/* Similar to yxml_setchar(), but will convert ch (any valid unicode point) to
 * UTF-8 and appends a '\0'. dest must have room for at least 5 bytes. */
fn void setutf8(char* dest, uint ch)
{
	switch (ch)
	{
		case 0..0x007F:
			setchar(dest, ch); dest++;
		case 0x0080..0x07FF:
			setchar(dest, 0xC0 | (ch>>6)); dest++;
			setchar(dest, 0x80 | (ch & 0x3F)); dest++;
		case 0x0800..0xFFFF:
			setchar(dest, 0xE0 | (ch>>12)); dest++;
			setchar(dest, 0x80 | ((ch>>6) & 0x3F)); dest++;
			setchar(dest, 0x80 | (ch & 0x3F)); dest++;
		default:
			setchar(dest, 0xF0 | (ch>>18)); dest++;
			setchar(dest, 0x80 | ((ch>>12) & 0x3F)); dest++;
			setchar(dest, 0x80 | ((ch>>6) & 0x3F)); dest++;
			setchar(dest, 0x80 | (ch & 0x3F)); dest++;
	}
	*dest = 0;
}

fn Ret datacontent(Parser* x, uint ch)
{
	setchar(&x.data[0], ch);
	x.data[1] = 0;
	return CONTENT;
}

fn Ret datapi1(Parser* x, uint ch)
{
	setchar(&x.data[0], ch);
	x.data[1] = 0;
	return PICONTENT;
}

fn Ret datapi2(Parser* x, uint ch)
{
	x.data[0] = '?';
	setchar(&x.data[1], ch);
	x.data[2] = 0;
	return PICONTENT;
}

fn Ret datacd1(Parser* x, uint ch)
{
	x.data[0] = ']';
	setchar(&x.data[1], ch);
	x.data[2] = 0;
	return CONTENT;
}

fn Ret datacd2(Parser* x, uint ch)
{
	x.data[0] = ']';
	x.data[1] = ']';
	setchar(&x.data[2], ch);
	x.data[3] = 0;
	return CONTENT;
}

fn Ret dataattr(Parser* x, uint ch)
{
	/* Normalize attribute values according to the XML spec section 3.3.3. */
	setchar(&x.data[0], ch == 0x9 || ch == 0xa ? 0x20 : ch);
	x.data[1] = 0;
	return ATTRVAL;
}

fn Ret pushstack(Parser* x, char** res, uint ch)
{
	if (x.stacklen+2 >= x.stacksize) return ESTACK;
	x.stacklen++;
	*res = (char *)x.stack+x.stacklen;
	x.stack[x.stacklen] = (char)ch;
	x.stacklen++;
	x.stack[x.stacklen] = 0;
	return OK;
}

fn Ret pushstackc(Parser* x, uint ch)
{
	if (x.stacklen+1 >= x.stacksize) return ESTACK;
	x.stack[x.stacklen] = (char)ch;
	x.stacklen++;
	x.stack[x.stacklen] = 0;
	return OK;
}

fn void popstack(Parser* x)
{
	do { x.stacklen--; }
	while (x.stack[x.stacklen] != 0);
}

fn Ret elemstart(Parser* x, uint ch)   => pushstack(x, &x.elem, ch);
fn Ret elemname(Parser* x, uint ch)    => pushstackc(x, ch);
fn Ret elemnameend(Parser* x, uint ch) => ELEMSTART;

/* Also used in elemcloseend(), since this function just removes the last
 * element from the stack and returns ELEMEND. */
fn Ret selfclose(Parser* x, uint ch)
{
	popstack(x);
	if (x.stacklen)
	{
		x.elem = (char*)x.stack+x.stacklen-1;
		while (*(x.elem - 1))
		{
			x.elem--;
		}
		return ELEMEND;
	}
	x.elem = (char*)x.stack;
	x.state = MISC3;
	return ELEMEND;
}

fn Ret elemclose(Parser* x, uint ch)
{
	if (*((char*)x.elem) != ch) return ECLOSE;
	x.elem++;
	return OK;
}

fn Ret elemcloseend(Parser* x, uint ch)
{
	if (*x.elem) return ECLOSE;
	return selfclose(x, ch);
}

fn Ret attrstart(Parser* x, uint ch)   => pushstack(x, &x.attr, ch);
fn Ret attrname(Parser* x, uint ch)    => pushstackc(x, ch);
fn Ret attrnameend(Parser* x, uint ch) => ATTRSTART;

fn Ret attrvalend(Parser* x, uint ch)
{
	popstack(x);
	return ATTREND;
}

fn Ret pistart(Parser* x, uint ch) => pushstack(x, &x.pi, ch);
fn Ret piname(Parser* x, uint ch)  => pushstackc(x, ch);

fn Ret piabort(Parser* x, uint ch)
{
	popstack(x);
	return OK;
}

fn Ret pinameend(Parser* x, uint ch) => (x.pi[0]|32) == 'x' && (x.pi[1]|32) == 'm' && (x.pi[2]|32) == 'l' && !x.pi[3] ? ESYN : PISTART;

fn Ret pivalend(Parser* x, uint ch)
{
	popstack(x); x.pi = (char *)x.stack;
	return PIEND;
}

fn Ret refstart(Parser* x, uint ch)
{
	mem::set(&x.data[0], 0, 8);
	x.reflen = 0;
	return OK;
}

fn Ret ref(Parser* x, uint ch)
{
	if (x.reflen >= x.data.len-1) return EREF;
	setchar(&x.data[x.reflen], ch);
	x.reflen++;
	return OK;
}

fn Ret refend(Parser* x, Ret ret)
{
	char* r = &x.data[0];
	uint ch = 0;
	if (*r == '#')
	{
		if (r[1] == 'x')
		{
			for (r += 2; isHex((uint)*r); r++)
			{
				ch = (ch<<4) + (*r <= '9' ? *r-'0' : (*r|32)-'a' + 10);
			}
		}
		else
		{
			for (r++; isNum((uint)*r); r++)
			{
				ch = (ch*10) + (*r-'0');
			}
		}
		if (*r)
		{
			ch = 0;
		}
	}
	else
	{
		ulong i = int_from_5_chars(r[0], r[1], r[2], r[3], r[4]);
		ch =
			i == int_from_5_chars('l','t', 0,  0, 0) ? '<' :
			i == int_from_5_chars('g','t', 0,  0, 0) ? '>' :
			i == int_from_5_chars('a','m','p', 0, 0) ? '&' :
			i == int_from_5_chars('a','p','o','s',0) ? '\'':
			i == int_from_5_chars('q','u','o','t',0) ? '"' : 0;
	}

	/* Codepoints not allowed in the XML 1.1 definition of a Char */
	if (!ch || ch > 0x10FFFF || ch == 0xFFFE || ch == 0xFFFF || (ch-0xDFFF) < 0x7FF) return EREF;
	setutf8(&x.data[0], ch);
	return ret;

}

fn Ret refcontent(Parser* x, uint ch) => refend(x, CONTENT);
fn Ret refattrval(Parser* x, uint ch) => refend(x, ATTRVAL);

fn void init(Parser* x, void* stack, usz stacksize)
{
	mem::clear(x, Parser::size);
	x.line = 1;
	x.stack = (char*)stack;
	x.stacksize = stacksize;
	*x.stack = 0;
	x.elem = x.pi = x.attr = (char*)x.stack;
	x.state = INIT;
}

fn Ret xml_parse_internal(Parser* x, int _ch)
{
	/* Ensure that characters are in the range of 0..255 rather than -126..125.
	 * All character comparisons are done with positive integers. */
	uint ch = (uint)(_ch+256) & 0xff;
	if (!ch) return ESYN;
	x.total++;

	/* End-of-Line normalization, "\rX", "\r\n" and "\n" are recognized and
	 * normalized to a single '\n' as per XML 1.0 section 2.11. XML 1.1 adds
	 * some non-ASCII character sequences to this list, but we can only handle
	 * ASCII here without making assumptions about the input encoding. */
	if (x.ignore == ch)
	{
		x.ignore = 0;
		return OK;
	}
	x.ignore = (ch == 0xd) ? 0xa : 0;
	if (ch == 0xa || ch == 0xd)
	{
		ch = 0xa;
		x.line++;
		x.byte = 0;
	}
	x.byte++;

	switch (x.state)
	{
		case STRING:
			if (ch == *x.string)
			{
				x.string++;
				if (!*x.string) x.state = x.nextstate;
				return OK;
			}
			break;
		case State.MISC2A:
			if (ch == '\x3b') {
				x.state = MISC2;
				return refcontent(x, ch);
		};
		case State.ENC3:
			if (x.quote == ch) {
				x.state = XMLDECL6;
				return OK;
		};
		case State.CD1:
			if (isChar(ch)) {
				x.state = CD0;
				return datacd1(x, ch);
		};
		case State.VER3:
			if (x.quote == ch) {
				x.state = XMLDECL4;
				return OK;
		};
		case State.COMMENT1:;
		case State.MISC1:
			if (ch == '<') {
				x.state = LE1;
				return OK;
		};
		case State.STD0:
			if (ch == '=') {
				x.state = STD1;
				return OK;
		};
		case State.XMLDECL7:
			if (ch == '?') {
				x.state = XMLDECL9;
				return OK;
		}
			if (ch == 's') {
				x.state = STRING;
				x.nextstate = STD0;
				x.string = "tandalone";
				return OK;
		};
		case State.XMLDECL2:
			if (isName(ch)) {
				x.state = PI1;
				return piname(x, ch);
		};
		case State.LEE2:
			if (ch == '[') {
				x.state = STRING;
				x.nextstate = CD0;
				x.string = "CDATA[";
				return OK;
		};
		case State.ETAG2:
			if (ch == '>') {
				x.state = MISC2;
				return OK;
		};
		case State.ELEM0:
			if (isSP(ch)) {
				x.state = ELEM1;
				return elemnameend(x, ch);
		}
			if (ch == '/') {
				x.state = ELEM3;
				return elemnameend(x, ch);
		}
			if (ch == '>') {
				x.state = MISC2;
				return elemnameend(x, ch);
		};
		case State.LE3:
			if (ch == '?') {
				x.state = PI0;
				x.nextstate = MISC3;
				return OK;
		};
		case State.VER0:
			if (ch == '=') {
				x.state = VER1;
				return OK;
		};
		case State.CD2:
			if (ch == '>') {
				x.state = MISC2;
				return OK;
		}
			if (isChar(ch)) {
				x.state = CD0;
				return datacd2(x, ch);
		};
		case State.DT0:
			if (ch == '\'' || ch == '"') {
				x.state = DT1;
				x.quote = ch;
				x.nextstate = DT0;
				return OK;
		}
			if (ch == '<') {
				x.state = DT2;
				return OK;
		}
			if (isChar(ch)) {
				return OK;
		};
		case State.PI0:;
		case State.LE1:
			if (ch == '?') {
				x.state = PI0;
				x.nextstate = MISC1;
				return OK;
		}
			if (isNameStart(ch)) {
				x.state = ELEM0;
				return elemstart(x, ch);
		};
		case State.COMMENT3:
			if (isChar(ch)) {
				x.state = COMMENT2;
				return OK;
		};
		case State.ELEM2:
			if (ch == '/') {
				x.state = ELEM3;
				return OK;
		}
			if (ch == '>') {
				x.state = MISC2;
				return OK;
		};
		case State.ETAG0:;
		case State.XMLDECL5:
			if (ch == '?') {
				x.state = XMLDECL9;
				return OK;
		}
			if (ch == 'e') {
				x.state = STRING;
				x.nextstate = ENC0;
				x.string = "ncoding";
				return OK;
		}
			if (ch == 's') {
				x.state = STRING;
				x.nextstate = STD0;
				x.string = "tandalone";
				return OK;
		};
		case State.ELEM3:;
		case State.ATTR4:
			if (ch == '\x3b') {
				x.state = ATTR3;
				return refattrval(x, ch);
		};
		case State.DT1:
			if (isChar(ch)) {
				return OK;
		};
		case State.ATTR1:
			if (ch == '=') {
				x.state = ATTR2;
				return OK;
		};
		case State.XMLDECL8:
			if (ch == '?') {
				x.state = XMLDECL9;
				return OK;
		};
		case State.ATTR3:
			if (ch == '&') {
				x.state = ATTR4;
				return refstart(x, ch);
		}
			if (x.quote == ch) {
				x.state = ELEM2;
				return attrvalend(x, ch);
		};
		case State.CD0:
			if (isChar(ch)) {
				return datacontent(x, ch);
		};
		case State.ETAG1:
			if (isSP(ch)) {
				x.state = ETAG2;
				return elemcloseend(x, ch);
		}
			if (ch == '>') {
				x.state = MISC2;
				return elemcloseend(x, ch);
		};
		case State.STD3:;
		case State.ELEM1:
			if (ch == '/') {
				x.state = ELEM3;
				return OK;
		}
			if (ch == '>') {
				x.state = MISC2;
				return OK;
		}
			if (isNameStart(ch)) {
				x.state = ATTR0;
				return attrstart(x, ch);
		};
		case State.DT2:
			if (ch == '!') {
				x.state = DT3;
				return OK;
		};
		case State.MISC2:
			if (ch == '&') {
				x.state = MISC2A;
				return refstart(x, ch);
		}
			if (isChar(ch)) {
				return datacontent(x, ch);
		};
		case State.PI1:
			if (ch == '?') {
				x.state = PI4;
				return pinameend(x, ch);
		}
			if (isSP(ch)) {
				x.state = PI2;
				return pinameend(x, ch);
		};
		case State.XMLDECL6:
			if (ch == '?') {
				x.state = XMLDECL9;
				return OK;
		};
		case State.ENC1:
			if (ch == '\'' || ch == '"') {
				x.state = ENC2;
				x.quote = ch;
				return OK;
		};
		case State.XMLDECL1:
			if (isName(ch)) {
				x.state = PI1;
				return piname(x, ch);
		}
			if (ch == '?') {
				x.state = PI4;
				return pinameend(x, ch);
		}
			if (isSP(ch)) {
				x.state = PI2;
				return pinameend(x, ch);
		};
		case State.XMLDECL0:
			if (isName(ch)) {
				x.state = PI1;
				return piname(x, ch);
		}
			if (ch == '?') {
				x.state = PI4;
				return pinameend(x, ch);
		}
			if (isSP(ch)) {
				x.state = PI2;
				return pinameend(x, ch);
		};
		case State.COMMENT4:;
		case State.MISC3:
			if (ch == '<') {
				x.state = LE3;
				return OK;
		};
		case State.ENC0:
			if (ch == '=') {
				x.state = ENC1;
				return OK;
		};
		case State.XMLDECL9:;
		case State.DT3:
			if (isChar(ch)) {
				x.state = DT4;
				return OK;
		};
		case State.PI3:
			if (isChar(ch)) {
				x.state = PI2;
				return datapi2(x, ch);
		};
		case State.LE2:
			if (ch == '?') {
				x.state = PI0;
				x.nextstate = MISC2;
				return OK;
		}
			if (ch == '/') {
				x.state = ETAG0;
				return OK;
		}
			if (isNameStart(ch)) {
				x.state = ELEM0;
				return elemstart(x, ch);
		};
		case State.LE0:
			if (ch == '?') {
				x.state = LEQ0;
				return OK;
		}
			if (isNameStart(ch)) {
				x.state = ELEM0;
				return elemstart(x, ch);
		};
		case State.PI4:;
		case State.LEE1:
			if (ch == 'D') {
				x.state = STRING;
				x.nextstate = DT0;
				x.string = "OCTYPE";
				return OK;
		};
		case State.COMMENT2:
			if (isChar(ch)) {
				return OK;
		};
		case State.STD1:
			if (ch == '\'' || ch == '"') {
				x.state = STD2;
				x.quote = ch;
				return OK;
		};
		case State.COMMENT0:;
		case State.ENC2:;
		case State.ATTR0:
			if (isSP(ch)) {
				x.state = ATTR1;
				return attrnameend(x, ch);
		}
			if (ch == '=') {
				x.state = ATTR2;
				return attrnameend(x, ch);
		};
		case State.INIT:
			if (isSP(ch)) {
				x.state = MISC0;
				return OK;
		}
			if (ch == '<') {
				x.state = LE0;
				return OK;
		};
		case State.DT4:
			if (ch == '>') {
				x.state = DT0;
				return OK;
		}
			if (isChar(ch)) {
				return OK;
		};
		case State.MISC0:
			if (ch == '<') {
				x.state = LE0;
				return OK;
		};
		case State.VER1:
			if (ch == '\'' || ch == '"') {
				x.state = STRING;
				x.quote = ch;
				x.nextstate = VER2;
				x.string = "1.";
				return OK;
		};
		case State.XMLDECL3:
			if (ch == 'v') {
				x.state = STRING;
				x.nextstate = VER0;
				x.string = "ersion";
				return OK;
		};
		case State.STD2:
			if (ch == 'n') {
				x.state = STRING;
				x.nextstate = STD3;
				x.string = "o";
				return OK;
		};
		case State.PI2:
			if (isChar(ch)) {
				return datapi1(x, ch);
		};
		case State.ATTR2:
			if (ch == '\'' || ch == '"') {
				x.state = ATTR3;
				x.quote = ch;
				return OK;
		};
		case State.XMLDECL4:
			if (ch == '?') {
				x.state = XMLDECL9;
				return OK;
		};
		case State.VER2:;
		case State.LEQ0:
			if (isNameStart(ch)) {
				x.state = PI1;
				x.nextstate = MISC1;
				return pistart(x, ch);
		}
		default:
			unreachable();
	}
	return ESYN;

}

/**
 * Returns the length of the element name (x->elem), attribute name (x->attr),
 * or PI name (x->pi). This function should ONLY be used directly after the
 * Ret.ELEMSTART, Ret.ATTRSTART or Ret.PISTART (respectively) tokens have
 * been returned by parse(), calling this at any other time may not give
 * the correct results. This function should also NOT be used on strings other
 * than x->elem, x->attr or x->pi.
 */
fn usz symlen(Parser* x, char* s) => (usz)((x.stack + x.stacklen) - s);

/**
 * May be called after the last character has been given to parse().
 * Returns Ret.OK if the XML document is valid, Ret.EEOF otherwise. Using
 * this function isn't really necessary, but can be used to detect documents
 * that don't end correctly. In particular, an error is returned when the XML
 * document did not contain a (complete) root element, or when the document
 * ended while in a comment or processing instruction.
 */
fn Ret eof(Parser* x)
{
	if (x.state != MISC3) return EEOF;
	return OK;
}
