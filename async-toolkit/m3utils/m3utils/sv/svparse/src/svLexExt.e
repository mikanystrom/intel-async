%source sv.t sv.l
%import svTok svLex

%module{
IMPORT Text;
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
