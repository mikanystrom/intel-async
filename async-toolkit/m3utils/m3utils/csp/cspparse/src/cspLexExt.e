%source csp.t csp.l
%import cspTok cspLex

T_IDENT: { val : TEXT }
T_IDENT { RETURN NEW(T_IDENT, val := $) }

T_INTEGER: { val : TEXT }
T_INTEGER { RETURN NEW(T_INTEGER, val := $) }

T_STRING_LIT: { val : TEXT }
T_STRING_LIT { RETURN NEW(T_STRING_LIT, val := $) }
