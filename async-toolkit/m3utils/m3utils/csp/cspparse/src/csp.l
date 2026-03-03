%macro {
ALPHA                   [a-zA-Z_]
DIGIT                   [0-9]
HEX                     [0-9a-fA-F]
BIN                     [01]
ESCQ                    \\\"
}

T_FUNCTION      "function"
T_STRUCTURE     "structure"
T_INT           "int"
T_SINT          "sint"
T_BOOL          "bool"
T_BOOLEAN       "boolean"
T_CONST         "const"
T_TRUE          "true"
T_FALSE         "false"
T_SKIP          "skip"
T_ERROR         "error"
T_ELSE          "else"
T_STRING        "string"
T_DIRECTIVES    "directives"

T_EQ            "=="
T_NEQ           "!="
T_LSASSIGN      "<<="
T_RSASSIGN      ">>="
T_LEQ           "<="
T_GEQ           ">="
T_ARROW         "->"
T_DOTDOT        ".."
T_COLON2        "::"
T_EXP           "**"
T_LSHIFT        "<<"
T_RSHIFT        ">>"
T_PIPE2         "||"
T_AMP2          "&&"
T_INC           "++"
T_DEC           "--"
T_PASSIGN       "+="
T_MASSIGN       "-="
T_TASSIGN       "*="
T_DASSIGN       "/="
T_RASSIGN       "%="
T_AASSIGN       "&="
T_OASSIGN       "|="
T_XASSIGN       "^="
T_BLOOP         "<||"
T_BOXLOOP       "<[]"
T_CLLOOP        "<:"
T_PLOOP         "<+"
T_MLOOP         "<*"
T_ALOOP         "<&"
T_OLOOP         "<|"
T_XLOOP         "<^"
T_SLOOP         "<;"
T_CLOOP         "<,"
T_BOX           "[]"
T_LOOP          "*["

T_IDENT         {ALPHA}({ALPHA}|{DIGIT})*
T_INTEGER       ({DIGIT}+("_"({ALPHA}|{DIGIT})+)?)|("0x""_"?{HEX}+("_"{HEX}+)*)|("0b""_"?{BIN}+("_"{BIN}+)*)
T_STRING_LIT    \"({ESCQ}|[^"])*\"

char            {%char}
skip            ([ \t\n]|("/*"([^*]|"*"[^/])*"*/")|("//"[^\n]*"\n"))*
ERROR           [^]
