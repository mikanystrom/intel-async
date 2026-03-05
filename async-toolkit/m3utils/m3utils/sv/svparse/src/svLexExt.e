%source sv.t sv.l
%import svTok svLex

T_IDENT: { val : TEXT }
T_IDENT { RETURN NEW(T_IDENT, val := $) }

T_NUMBER: { val : TEXT }
T_NUMBER { RETURN NEW(T_NUMBER, val := $) }

T_STRLIT: { val : TEXT }
T_STRLIT { RETURN NEW(T_STRLIT, val := $) }

T_SYSIDENT: { val : TEXT }
T_SYSIDENT { RETURN NEW(T_SYSIDENT, val := $) }

T_DIRECTIVE: { val : TEXT }
T_DIRECTIVE { RETURN NEW(T_DIRECTIVE, val := $) }
