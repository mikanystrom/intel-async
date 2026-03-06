#!/usr/bin/env python3
"""SystemVerilog preprocessor.

Handles `define (with parameters), `undef, `ifdef, `ifndef, `else,
`elsif, `endif, `include, and macro expansion. Outputs preprocessed
SV to stdout with line counts preserved (directive lines become blank)
so that parser error messages refer to correct line numbers.

Usage: svpp.py [-I dir]... [-D NAME[=VALUE]]... file.sv
"""

import sys, os, re, argparse


class Macro:
    """A defined macro, possibly with parameters."""
    __slots__ = ('body', 'params', 'defaults')

    def __init__(self, body, params=None, defaults=None):
        self.body = body
        self.params = params  # None = simple macro, list = param names
        self.defaults = defaults  # None or list of default values (None = no default)


def preprocess(filename, defines, include_dirs, seen_files=None):
    if seen_files is None:
        seen_files = set()
    realpath = os.path.realpath(filename)
    if realpath in seen_files:
        return []
    seen_files.add(realpath)

    filedir = os.path.dirname(os.path.abspath(filename))
    try:
        with open(filename, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"svpp: cannot open '{filename}'", file=sys.stderr)
        sys.exit(1)

    output = []
    cond_stack = []

    def is_active():
        return all(active for active, _ in cond_stack)

    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        stripped = line.rstrip('\n').rstrip('\r')
        m = re.match(r'\s*`(\w+)(.*)', stripped)
        if m:
            directive = m.group(1)
            rest = m.group(2)

            if directive == 'define':
                # Join backslash-continuation lines
                full_rest = rest
                output.append('\n')
                while full_rest.rstrip().endswith('\\') and i < len(lines):
                    full_rest = full_rest.rstrip()[:-1] + ' ' + lines[i].rstrip('\n').rstrip('\r')
                    i += 1
                    output.append('\n')
                if is_active():
                    parse_define(full_rest.strip(), defines)
                continue

            elif directive == 'undef':
                if is_active():
                    defines.pop(rest.strip(), None)
                output.append('\n')
                continue

            elif directive == 'ifdef':
                name = rest.strip()
                active = name in defines if is_active() else False
                cond_stack.append((active, active))
                output.append('\n')
                continue

            elif directive == 'ifndef':
                name = rest.strip()
                active = name not in defines if is_active() else False
                cond_stack.append((active, active))
                output.append('\n')
                continue

            elif directive == 'elsif':
                if cond_stack:
                    _, seen_true = cond_stack.pop()
                    name = rest.strip()
                    parent_active = all(active for active, _ in cond_stack)
                    if parent_active and not seen_true and name in defines:
                        cond_stack.append((True, True))
                    else:
                        cond_stack.append((False, seen_true))
                output.append('\n')
                continue

            elif directive == 'else':
                if cond_stack:
                    _, seen_true = cond_stack.pop()
                    parent_active = all(active for active, _ in cond_stack)
                    cond_stack.append((parent_active and not seen_true, True))
                output.append('\n')
                continue

            elif directive == 'endif':
                if cond_stack:
                    cond_stack.pop()
                output.append('\n')
                continue

            elif directive == 'include':
                if is_active():
                    im = re.match(r'\s*"([^"]+)"', rest)
                    if im:
                        incname = im.group(1)
                        incpath = find_include(incname, filedir, include_dirs)
                        if incpath:
                            preprocess(incpath, defines, include_dirs,
                                       seen_files)
                output.append('\n')
                continue

            elif directive in ('timescale', 'resetall', 'default_nettype',
                               'celldefine', 'endcelldefine'):
                output.append('\n')
                continue

        if not is_active():
            output.append('\n')
            continue

        # Join continuation lines for multi-line macro invocations
        joined = stripped
        extra_lines = 0
        while has_unclosed_macro_args(joined, defines) and i < len(lines):
            joined += '\n' + lines[i].rstrip('\n').rstrip('\r')
            i += 1
            extra_lines += 1

        expanded = expand_macros(joined, defines)
        for exp_line in expanded.split('\n'):
            output.append(exp_line + '\n')

    return output


def parse_define(rest, defines):
    """Parse a `define directive body into a Macro."""
    # Match: NAME(param,param) body  or  NAME body
    m = re.match(r'(\w+)\(([^)]*)\)\s*(.*)', rest)
    if m:
        name = m.group(1)
        raw_params = [p.strip() for p in m.group(2).split(',')]
        body = m.group(3)
        params = []
        defaults = []
        for p in raw_params:
            if '=' in p:
                pname, pdefault = p.split('=', 1)
                params.append(pname.strip())
                defaults.append(pdefault.strip())
            else:
                params.append(p)
                defaults.append(None)
        defines[name] = Macro(body, params, defaults)
    else:
        m = re.match(r'(\w+)\s*(.*)', rest)
        if m:
            defines[m.group(1)] = Macro(m.group(2))


def has_unclosed_macro_args(text, defines):
    """Check if text contains a known parameterized macro with unclosed parens."""
    for m in re.finditer(r'`(\w+)', text):
        name = m.group(1)
        if name in defines:
            macro = defines[name]
            if isinstance(macro, Macro) and macro.params is not None:
                after = m.end()
                if after < len(text) and text[after] == '(':
                    # Count parens from here
                    depth = 0
                    for c in text[after:]:
                        if c == '(':
                            depth += 1
                        elif c == ')':
                            depth -= 1
                            if depth == 0:
                                break
                    if depth > 0:
                        return True
    return False


def expand_macros(line, defines):
    """Expand `MACRO and `MACRO(args) references, recursively."""
    max_iterations = 50
    for _ in range(max_iterations):
        new_line = _expand_once(line, defines)
        if new_line == line:
            break
        line = new_line
    # Process conditional directives that emerged from macro expansion
    line = _process_inline_conditionals(line, defines)
    return line


def _process_inline_conditionals(text, defines):
    """Handle `ifdef/`ifndef/`else/`endif that appear after macro expansion."""
    # These can appear on a single line from multi-line macro bodies joined together
    cond_re = re.compile(r'`(ifdef|ifndef|elsif|else|endif)\b\s*(\w*)')
    if not cond_re.search(text):
        return text
    # Process by splitting into segments
    result = []
    cond_stack = []
    pos = 0
    for m in cond_re.finditer(text):
        directive = m.group(1)
        name = m.group(2)
        # Add text before this directive if currently active
        if all(cond_stack) if cond_stack else True:
            result.append(text[pos:m.start()])
        if directive == 'ifdef':
            cond_stack.append(name in defines)
        elif directive == 'ifndef':
            cond_stack.append(name not in defines)
        elif directive == 'else':
            if cond_stack:
                cond_stack[-1] = not cond_stack[-1]
        elif directive == 'elsif':
            if cond_stack:
                cond_stack[-1] = name in defines
        elif directive == 'endif':
            if cond_stack:
                cond_stack.pop()
        pos = m.end()
    # Add remaining text
    if all(cond_stack) if cond_stack else True:
        result.append(text[pos:])
    return ''.join(result)


def _expand_once(line, defines):
    """Single pass of macro expansion."""
    result = []
    i = 0
    while i < len(line):
        if line[i] == '`':
            m = re.match(r'`(\w+)', line[i:])
            if m:
                name = m.group(1)
                after = i + len(m.group(0))
                if name in defines:
                    macro = defines[name]
                    if isinstance(macro, Macro) and macro.params is not None:
                        # Parameterized macro — look for (args)
                        args, end = parse_macro_args(line, after)
                        if args is not None:
                            # Fill in defaults for missing arguments
                            full_args = list(args)
                            if macro.defaults:
                                while len(full_args) < len(macro.params):
                                    idx = len(full_args)
                                    if idx < len(macro.defaults) and macro.defaults[idx] is not None:
                                        full_args.append(macro.defaults[idx])
                                    else:
                                        break
                            body = macro.body
                            for p, a in zip(macro.params, full_args):
                                body = body.replace(p, a)
                            # Handle `` (token pasting operator)
                            body = body.replace('``', '')
                            result.append(body)
                            i = end
                            continue
                        else:
                            # No args provided — leave unexpanded
                            result.append(m.group(0))
                            i = after
                            continue
                    else:
                        # Simple macro
                        body = macro.body if isinstance(macro, Macro) else macro
                        result.append(body)
                        i = after
                        continue
                else:
                    result.append(m.group(0))
                    i = after
                    continue
        result.append(line[i])
        i += 1
    return ''.join(result)


def parse_macro_args(line, pos):
    """Parse macro arguments starting at pos, expecting '(' ... ')'.
    Returns (list_of_args, end_pos) or (None, pos) if no parens."""
    if pos >= len(line) or line[pos] != '(':
        return None, pos
    depth = 1
    start = pos + 1
    args = []
    i = start
    while i < len(line):
        c = line[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                args.append(line[start:i].strip())
                return args, i + 1
        elif c == ',' and depth == 1:
            args.append(line[start:i].strip())
            start = i + 1
        i += 1
    return None, pos


def find_include(name, filedir, include_dirs):
    """Search for an include file."""
    path = os.path.join(filedir, name)
    if os.path.isfile(path):
        return path
    for d in include_dirs:
        path = os.path.join(d, name)
        if os.path.isfile(path):
            return path
    return None


def main():
    parser = argparse.ArgumentParser(description='SystemVerilog preprocessor')
    parser.add_argument('-I', action='append', default=[], dest='include_dirs',
                        help='Add include search directory')
    parser.add_argument('-D', action='append', default=[], dest='cmdline_defines',
                        help='Define macro (NAME or NAME=VALUE)')
    parser.add_argument('filename', help='Input SystemVerilog file')
    args = parser.parse_args()

    defines = {}
    for d in args.cmdline_defines:
        if '=' in d:
            name, value = d.split('=', 1)
            defines[name] = Macro(value)
        else:
            defines[d] = Macro('1')

    output = preprocess(args.filename, defines, args.include_dirs)
    sys.stdout.writelines(output)


if __name__ == '__main__':
    main()
