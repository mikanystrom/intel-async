%source sv.t sv.l
%import svTok svLex

%public {
  curLine : INTEGER := 1;
  curFile : TEXT := "";
  prevEnd : INTEGER := 0;
}

%overrides {
  get := MyGet;
}

%module{
IMPORT svTok, Text, Rd;
<* FATAL Rd.EndOfFile *>

PROCEDURE CountNewlines(self: T; from, to: INTEGER) =
  VAR rd := self.getRd();
  BEGIN
    IF to > from THEN
      Rd.Seek(rd, from);
      FOR i := from TO to - 1 DO
        IF Rd.GetChar(rd) = '\n' THEN INC(self.curLine) END
      END
    END
  END CountNewlines;

PROCEDURE StartsWith(t, prefix: TEXT): BOOLEAN =
  VAR tl := Text.Length(t); pl := Text.Length(prefix);
  BEGIN
    RETURN tl >= pl AND Text.Equal(Text.Sub(t, 0, pl), prefix)
  END StartsWith;

PROCEDURE IsLineDirective(val: TEXT): BOOLEAN =
  BEGIN
    RETURN StartsWith(val, "`line ")
       OR  StartsWith(val, "`line\t")
  END IsLineDirective;

PROCEDURE ParseLineDirective(self: T; val: TEXT) =
  VAR
    len := Text.Length(val);
    i   : INTEGER;
    numStart, numEnd: INTEGER;
    q1, q2: INTEGER;
  BEGIN
    (* Skip "`line" and whitespace *)
    i := 5;
    WHILE i < len AND (Text.GetChar(val, i) = ' '
                       OR Text.GetChar(val, i) = '\t') DO
      INC(i)
    END;
    (* Parse line number *)
    numStart := i;
    WHILE i < len AND Text.GetChar(val, i) >= '0'
                  AND Text.GetChar(val, i) <= '9' DO
      INC(i)
    END;
    numEnd := i;
    IF numEnd > numStart THEN
      self.curLine := 0;
      FOR j := numStart TO numEnd - 1 DO
        self.curLine := self.curLine * 10
          + ORD(Text.GetChar(val, j)) - ORD('0')
      END
    END;
    (* Skip whitespace, parse optional filename *)
    WHILE i < len AND (Text.GetChar(val, i) = ' '
                       OR Text.GetChar(val, i) = '\t') DO
      INC(i)
    END;
    IF i < len AND Text.GetChar(val, i) = '"' THEN
      q1 := i + 1;
      q2 := Text.FindChar(val, '"', q1);
      IF q2 > q1 THEN
        self.curFile := Text.Sub(val, q1, q2 - q1)
      END
    END
  END ParseLineDirective;

PROCEDURE MyGet(self: T): svTok.Token RAISES {Rd.EndOfFile} =
  VAR
    tok    : svTok.Token;
    rd     := self.getRd();
    curPos : INTEGER;
  BEGIN
    tok := svLex.T.get(self);
    curPos := Rd.Index(rd);
    (* Count newlines in skip region AND token text *)
    CountNewlines(self, self.prevEnd, curPos);
    Rd.Seek(rd, curPos);
    self.prevEnd := curPos;
    (* Handle `line directives transparently *)
    TYPECASE tok OF
    | T_DIRECTIVE(d) =>
      IF IsLineDirective(d.val) THEN
        ParseLineDirective(self, d.val);
        RETURN MyGet(self)
      END
    ELSE
    END;
    RETURN tok
  END MyGet;
}

T_IDENT: { val : TEXT }
T_IDENT { RETURN NEW(T_IDENT, val := $) }

T_NUMBER: { val : TEXT }
T_NUMBER {
  VAR i := Text.FindChar($, '\'');
  BEGIN
    IF i >= 0 THEN
      RETURN NEW(T_NUMBER, val := Text.Sub($, 0, i) & ":" & Text.Sub($, i+1, LAST(CARDINAL)))
    ELSE
      RETURN NEW(T_NUMBER, val := $)
    END
  END
}

T_STRLIT: { val : TEXT }
T_STRLIT { RETURN NEW(T_STRLIT, val := $) }

T_SYSIDENT: { val : TEXT }
T_SYSIDENT { RETURN NEW(T_SYSIDENT, val := $) }

T_DIRECTIVE: { val : TEXT }
T_DIRECTIVE { RETURN NEW(T_DIRECTIVE, val := $) }

T_ANNOTATION: { val : TEXT }
T_TRANSLATE_OFF: { val : TEXT }
T_TRANSLATE_ON: { val : TEXT }

T_LINE_COMMENT: {}
T_LINE_COMMENT {
  VAR
    text := $;
    len  := Text.Length(text);
    i    : INTEGER;
  BEGIN
    (* Skip "//" and whitespace *)
    i := 2;
    WHILE i < len AND (Text.GetChar(text, i) = ' '
                       OR Text.GetChar(text, i) = '\t') DO
      INC(i)
    END;
    (* Check for annotation: // @keyword *)
    IF i < len AND Text.GetChar(text, i) = '@' THEN
      RETURN NEW(T_ANNOTATION, val := text)
    END;
    (* Check for synopsys translate_off/on *)
    IF StartsWith(Text.Sub(text, i), "synopsys") THEN
      INC(i, 8);
      WHILE i < len AND (Text.GetChar(text, i) = ' '
                         OR Text.GetChar(text, i) = '\t') DO
        INC(i)
      END;
      IF StartsWith(Text.Sub(text, i), "translate_off") THEN
        RETURN NEW(T_TRANSLATE_OFF, val := text)
      ELSIF StartsWith(Text.Sub(text, i), "translate_on") THEN
        RETURN NEW(T_TRANSLATE_ON, val := text)
      END
    END;
    (* Regular comment -- skip *)
    RETURN NIL
  END
}

T_BLOCK_COMMENT: {}
T_BLOCK_COMMENT { RETURN NIL }
