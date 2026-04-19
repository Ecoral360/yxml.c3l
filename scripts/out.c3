constdef YxmlRet {
	YXML_EEOF        = -5, /* Unexpected EOF                             */
	YXML_EREF        = -4, /* Invalid character or entity reference (&whatever;) */
	YXML_ECLOSE      = -3, /* Close tag does not match open tag (<Tag> .. </OtherTag>) */
	YXML_ESTACK      = -2, /* Stack overflow (too deeply nested tags or too long element/attribute name) */
	YXML_ESYN        = -1, /* Syntax error (unexpected byte)             */
	YXML_OK          =  0, /* Character consumed, no new token present   */
	YXML_ELEMSTART   =  1, /* Start of an element:   '<Tag ..'           */
	YXML_CONTENT     =  2, /* Element content                            */
	YXML_ELEMEND     =  3, /* End of an element:     '.. />' or '</Tag>' */
	YXML_ATTRSTART   =  4, /* Attribute:             'Name=..'           */
	YXML_ATTRVAL     =  5, /* Attribute value                            */
	YXML_ATTREND     =  6, /* End of attribute       '.."'               */
	YXML_PISTART     =  7, /* Start of a processing instruction          */
	YXML_PICONTENT   =  8, /* Content of a PI                            */
	YXML_PIEND       =  9  /* End of a processing instruction            */
} 

struct Yxml {
	/* PUBLIC (read-only) */

	/* Name of the current element, zero-length if not in any element. Changed
	 * after YXML_ELEMSTART. The pointer will remain valid up to and including
	 * the next non-YXML_ATTR* token, the pointed-to buffer will remain valid
	 * up to and including the YXML_ELEMEND for the corresponding element. */
	char *elem;

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
	char *attr;

	/* Name/target of the current processing instruction, zero-length if not in
	 * a PI. Changed after YXML_PISTART, valid up to (but excluding)
	 * the next YXML_PIEND. */
	char *pi;

	/* Line number, byte offset within that line, and total bytes read. These
	 * values refer to the position _after_ the last byte given to
	 * yxml_parse(). These are useful for debugging and error reporting. */
	ulong byte;
	ulong total;
	uint line;


	/* PRIVATE */
	YxmlState state;
	char *stack; /* Stack of element names + attribute/PI name, separated by \0. Also starts with a \0. */
	isz stacksize, stacklen;
	usz reflen;
	usz quote;
	YxmlState nextstate; /* Used for '@' state remembering and for the "string" consuming state */
	usz ignore;
	char *string;
}

enum YxmlState {
  YXMLS_STRING,
  YXMLS_MISC2A,
YXMLS_ENC3,
YXMLS_CD1,
YXMLS_VER3,
YXMLS_COMMENT1,
YXMLS_MISC1,
YXMLS_STD0,
YXMLS_XMLDECL7,
YXMLS_XMLDECL2,
YXMLS_LEE2,
YXMLS_ETAG2,
YXMLS_ELEM0,
YXMLS_LE3,
YXMLS_VER0,
YXMLS_CD2,
YXMLS_DT0,
YXMLS_PI0,
YXMLS_LE1,
YXMLS_COMMENT3,
YXMLS_ELEM2,
YXMLS_ETAG0,
YXMLS_XMLDECL5,
YXMLS_ELEM3,
YXMLS_ATTR4,
YXMLS_DT1,
YXMLS_ATTR1,
YXMLS_XMLDECL8,
YXMLS_ATTR3,
YXMLS_CD0,
YXMLS_ETAG1,
YXMLS_STD3,
YXMLS_ELEM1,
YXMLS_DT2,
YXMLS_MISC2,
YXMLS_PI1,
YXMLS_XMLDECL6,
YXMLS_ENC1,
YXMLS_XMLDECL1,
YXMLS_XMLDECL0,
YXMLS_COMMENT4,
YXMLS_MISC3,
YXMLS_ENC0,
YXMLS_XMLDECL9,
YXMLS_DT3,
YXMLS_PI3,
YXMLS_LE2,
YXMLS_LE0,
YXMLS_PI4,
YXMLS_LEE1,
YXMLS_COMMENT2,
YXMLS_STD1,
YXMLS_COMMENT0,
YXMLS_ENC2,
YXMLS_ATTR0,
YXMLS_INIT,
YXMLS_DT4,
YXMLS_MISC0,
YXMLS_VER1,
YXMLS_XMLDECL3,
YXMLS_STD2,
YXMLS_PI2,
YXMLS_ATTR2,
YXMLS_XMLDECL4,
YXMLS_VER2,
YXMLS_LEQ0,

}


fn YxmlRet yxml_parse(Yxml *x, int _ch) {
  /* Ensure that characters are in the range of 0..255 rather than -126..125.
   * All character comparisons are done with positive integers. */
  usz ch = (usz)(_ch+256) & 0xff;
  if(!ch) { 
    return YXML_ESYN;
  }
  x.total++;

  /* End-of-Line normalization, "\rX", "\r\n" and "\n" are recognized and
   * normalized to a single '\n' as per XML 1.0 section 2.11. XML 1.1 adds
   * some non-ASCII character sequences to this list, but we can only handle
   * ASCII here without making assumptions about the input encoding. */
  if(x.ignore == ch) {
    x.ignore = 0;
    return YXML_OK;
  }
  x.ignore = ((usz) (ch == 0xd)) * 0xa;
  if(ch == 0xa || ch == 0xd) {
    ch = 0xa;
    x.line++;
    x.byte = 0;
  }
  x.byte++;

  switch((YxmlState)x.state) {
    case YXMLS_STRING:
      if(ch == *x.string) {
        x.string++;
        if(!*x.string) {
          x.state = x.nextstate;
        }
        return YXML_OK;
      }
      break;
    case YxmlState.YXMLS_MISC2A:
	if ('\x3b') {
		x.state = YXMLS_MISC2;
		return yxml_refcontent(x, ch);
};
case YxmlState.YXMLS_ENC3:
	if (x.quote = ch) {
		x.state = YXMLS_XMLDECL6;
		return YXML_OK;
};
case YxmlState.YXMLS_CD1:
	if (yxml_isChar(ch)) {
		x.state = YXMLS_CD0;
		return yxml_datacd1(x, ch);
};
case YxmlState.YXMLS_VER3:
	if (x.quote = ch) {
		x.state = YXMLS_XMLDECL4;
		return YXML_OK;
};
case YxmlState.YXMLS_COMMENT1:;
case YxmlState.YXMLS_MISC1:
	if ('<') {
		x.state = YXMLS_LE1;
		return YXML_OK;
};
case YxmlState.YXMLS_STD0:
	if ('=') {
		x.state = YXMLS_STD1;
		return YXML_OK;
};
case YxmlState.YXMLS_XMLDECL7:
	if ('?') {
		x.state = YXMLS_XMLDECL9;
		return YXML_OK;
}
	if ('s') {
		x.state = YXMLS_STRING;
		x.nextstate = YXMLS_STD0;
		x.string = "tandalone";
		return YXML_OK;
};
case YxmlState.YXMLS_XMLDECL2:
	if (yxml_isName(ch)) {
		x.state = YXMLS_PI1;
		return yxml_piname(x, ch);
};
case YxmlState.YXMLS_LEE2:
	if ('[') {
		x.state = YXMLS_STRING;
		x.nextstate = YXMLS_CD0;
		x.string = "CDATA[";
		return YXML_OK;
};
case YxmlState.YXMLS_ETAG2:
	if ('>') {
		x.state = YXMLS_MISC2;
		return YXML_OK;
};
case YxmlState.YXMLS_ELEM0:
	if (yxml_isSP(ch)) {
		x.state = YXMLS_ELEM1;
		return yxml_elemnameend(x, ch);
}
	if ('/') {
		x.state = YXMLS_ELEM3;
		return yxml_elemnameend(x, ch);
}
	if ('>') {
		x.state = YXMLS_MISC2;
		return yxml_elemnameend(x, ch);
};
case YxmlState.YXMLS_LE3:
	if ('?') {
		x.state = YXMLS_PI0;
		x.nextstate = YXMLS_MISC3;
		return YXML_OK;
};
case YxmlState.YXMLS_VER0:
	if ('=') {
		x.state = YXMLS_VER1;
		return YXML_OK;
};
case YxmlState.YXMLS_CD2:
	if ('>') {
		x.state = YXMLS_MISC2;
		return YXML_OK;
}
	if (yxml_isChar(ch)) {
		x.state = YXMLS_CD0;
		return yxml_datacd2(x, ch);
};
case YxmlState.YXMLS_DT0:
	if ('\'' || '"') {
		x.state = YXMLS_DT1;
		x.quote = ch;
		x.nextstate = YXMLS_DT0;
		return YXML_OK;
}
	if ('<') {
		x.state = YXMLS_DT2;
		return YXML_OK;
}
	if (yxml_isChar(ch)) {
		return YXML_OK;
};
case YxmlState.YXMLS_PI0:;
case YxmlState.YXMLS_LE1:
	if ('?') {
		x.state = YXMLS_PI0;
		x.nextstate = YXMLS_MISC1;
		return YXML_OK;
}
	if (yxml_isNameStart(ch)) {
		x.state = YXMLS_ELEM0;
		return yxml_elemstart(x, ch);
};
case YxmlState.YXMLS_COMMENT3:
	if (yxml_isChar(ch)) {
		x.state = YXMLS_COMMENT2;
		return YXML_OK;
};
case YxmlState.YXMLS_ELEM2:
	if ('/') {
		x.state = YXMLS_ELEM3;
		return YXML_OK;
}
	if ('>') {
		x.state = YXMLS_MISC2;
		return YXML_OK;
};
case YxmlState.YXMLS_ETAG0:;
case YxmlState.YXMLS_XMLDECL5:
	if ('?') {
		x.state = YXMLS_XMLDECL9;
		return YXML_OK;
}
	if ('e') {
		x.state = YXMLS_STRING;
		x.nextstate = YXMLS_ENC0;
		x.string = "ncoding";
		return YXML_OK;
}
	if ('s') {
		x.state = YXMLS_STRING;
		x.nextstate = YXMLS_STD0;
		x.string = "tandalone";
		return YXML_OK;
};
case YxmlState.YXMLS_ELEM3:;
case YxmlState.YXMLS_ATTR4:
	if ('\x3b') {
		x.state = YXMLS_ATTR3;
		return yxml_refattrval(x, ch);
};
case YxmlState.YXMLS_DT1:
	if (yxml_isChar(ch)) {
		return YXML_OK;
};
case YxmlState.YXMLS_ATTR1:
	if ('=') {
		x.state = YXMLS_ATTR2;
		return YXML_OK;
};
case YxmlState.YXMLS_XMLDECL8:
	if ('?') {
		x.state = YXMLS_XMLDECL9;
		return YXML_OK;
};
case YxmlState.YXMLS_ATTR3:
	if ('&') {
		x.state = YXMLS_ATTR4;
		return yxml_refstart(x, ch);
}
	if (x.quote = ch) {
		x.state = YXMLS_ELEM2;
		return yxml_attrvalend(x, ch);
};
case YxmlState.YXMLS_CD0:
	if (yxml_isChar(ch)) {
		return yxml_datacontent(x, ch);
};
case YxmlState.YXMLS_ETAG1:
	if (yxml_isSP(ch)) {
		x.state = YXMLS_ETAG2;
		return yxml_elemcloseend(x, ch);
}
	if ('>') {
		x.state = YXMLS_MISC2;
		return yxml_elemcloseend(x, ch);
};
case YxmlState.YXMLS_STD3:;
case YxmlState.YXMLS_ELEM1:
	if ('/') {
		x.state = YXMLS_ELEM3;
		return YXML_OK;
}
	if ('>') {
		x.state = YXMLS_MISC2;
		return YXML_OK;
}
	if (yxml_isNameStart(ch)) {
		x.state = YXMLS_ATTR0;
		return yxml_attrstart(x, ch);
};
case YxmlState.YXMLS_DT2:
	if ('!') {
		x.state = YXMLS_DT3;
		return YXML_OK;
};
case YxmlState.YXMLS_MISC2:
	if ('&') {
		x.state = YXMLS_MISC2A;
		return yxml_refstart(x, ch);
}
	if (yxml_isChar(ch)) {
		return yxml_datacontent(x, ch);
};
case YxmlState.YXMLS_PI1:
	if ('?') {
		x.state = YXMLS_PI4;
		return yxml_pinameend(x, ch);
}
	if (yxml_isSP(ch)) {
		x.state = YXMLS_PI2;
		return yxml_pinameend(x, ch);
};
case YxmlState.YXMLS_XMLDECL6:
	if ('?') {
		x.state = YXMLS_XMLDECL9;
		return YXML_OK;
};
case YxmlState.YXMLS_ENC1:
	if ('\'' || '"') {
		x.state = YXMLS_ENC2;
		x.quote = ch;
		return YXML_OK;
};
case YxmlState.YXMLS_XMLDECL1:
	if (yxml_isName(ch)) {
		x.state = YXMLS_PI1;
		return yxml_piname(x, ch);
}
	if ('?') {
		x.state = YXMLS_PI4;
		return yxml_pinameend(x, ch);
}
	if (yxml_isSP(ch)) {
		x.state = YXMLS_PI2;
		return yxml_pinameend(x, ch);
};
case YxmlState.YXMLS_XMLDECL0:
	if (yxml_isName(ch)) {
		x.state = YXMLS_PI1;
		return yxml_piname(x, ch);
}
	if ('?') {
		x.state = YXMLS_PI4;
		return yxml_pinameend(x, ch);
}
	if (yxml_isSP(ch)) {
		x.state = YXMLS_PI2;
		return yxml_pinameend(x, ch);
};
case YxmlState.YXMLS_COMMENT4:;
case YxmlState.YXMLS_MISC3:
	if ('<') {
		x.state = YXMLS_LE3;
		return YXML_OK;
};
case YxmlState.YXMLS_ENC0:
	if ('=') {
		x.state = YXMLS_ENC1;
		return YXML_OK;
};
case YxmlState.YXMLS_XMLDECL9:;
case YxmlState.YXMLS_DT3:
	if (yxml_isChar(ch)) {
		x.state = YXMLS_DT4;
		return YXML_OK;
};
case YxmlState.YXMLS_PI3:
	if (yxml_isChar(ch)) {
		x.state = YXMLS_PI2;
		return yxml_datapi2(x, ch);
};
case YxmlState.YXMLS_LE2:
	if ('?') {
		x.state = YXMLS_PI0;
		x.nextstate = YXMLS_MISC2;
		return YXML_OK;
}
	if ('/') {
		x.state = YXMLS_ETAG0;
		return YXML_OK;
}
	if (yxml_isNameStart(ch)) {
		x.state = YXMLS_ELEM0;
		return yxml_elemstart(x, ch);
};
case YxmlState.YXMLS_LE0:
	if ('?') {
		x.state = YXMLS_LEQ0;
		return YXML_OK;
}
	if (yxml_isNameStart(ch)) {
		x.state = YXMLS_ELEM0;
		return yxml_elemstart(x, ch);
};
case YxmlState.YXMLS_PI4:;
case YxmlState.YXMLS_LEE1:
	if ('D') {
		x.state = YXMLS_STRING;
		x.nextstate = YXMLS_DT0;
		x.string = "OCTYPE";
		return YXML_OK;
};
case YxmlState.YXMLS_COMMENT2:
	if (yxml_isChar(ch)) {
		return YXML_OK;
};
case YxmlState.YXMLS_STD1:
	if ('\'' || '"') {
		x.state = YXMLS_STD2;
		x.quote = ch;
		return YXML_OK;
};
case YxmlState.YXMLS_COMMENT0:;
case YxmlState.YXMLS_ENC2:;
case YxmlState.YXMLS_ATTR0:
	if (yxml_isSP(ch)) {
		x.state = YXMLS_ATTR1;
		return yxml_attrnameend(x, ch);
}
	if ('=') {
		x.state = YXMLS_ATTR2;
		return yxml_attrnameend(x, ch);
};
case YxmlState.YXMLS_INIT:
	if (yxml_isSP(ch)) {
		x.state = YXMLS_MISC0;
		return YXML_OK;
}
	if ('<') {
		x.state = YXMLS_LE0;
		return YXML_OK;
};
case YxmlState.YXMLS_DT4:
	if ('>') {
		x.state = YXMLS_DT0;
		return YXML_OK;
}
	if (yxml_isChar(ch)) {
		return YXML_OK;
};
case YxmlState.YXMLS_MISC0:
	if ('<') {
		x.state = YXMLS_LE0;
		return YXML_OK;
};
case YxmlState.YXMLS_VER1:
	if ('\'' || '"') {
		x.state = YXMLS_STRING;
		x.quote = ch;
		x.nextstate = YXMLS_VER2;
		x.string = "1.";
		return YXML_OK;
};
case YxmlState.YXMLS_XMLDECL3:
	if ('v') {
		x.state = YXMLS_STRING;
		x.nextstate = YXMLS_VER0;
		x.string = "ersion";
		return YXML_OK;
};
case YxmlState.YXMLS_STD2:
	if ('n') {
		x.state = YXMLS_STRING;
		x.nextstate = YXMLS_STD3;
		x.string = "o";
		return YXML_OK;
};
case YxmlState.YXMLS_PI2:
	if (yxml_isChar(ch)) {
		return yxml_datapi1(x, ch);
};
case YxmlState.YXMLS_ATTR2:
	if ('\'' || '"') {
		x.state = YXMLS_ATTR3;
		x.quote = ch;
		return YXML_OK;
};
case YxmlState.YXMLS_XMLDECL4:
	if ('?') {
		x.state = YXMLS_XMLDECL9;
		return YXML_OK;
};
case YxmlState.YXMLS_VER2:;
case YxmlState.YXMLS_LEQ0:
	if (yxml_isNameStart(ch)) {
		x.state = YXMLS_PI1;
		x.nextstate = YXMLS_MISC1;
		return yxml_pistart(x, ch);
}
  }
  return YXML_ESYN;
}



