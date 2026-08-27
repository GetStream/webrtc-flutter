"""Flags ObjC accessors that recurse into themselves.

An @property synthesizes `x` / `setX:`. A method defined with that same selector
*replaces* the synthesized accessor. If its body then uses `self.x`, the dot
syntax compiles to a message send of that very selector and the method calls
itself until the stack runs out.

Hand-written accessors backed by associated objects or ivars are fine and are
not flagged, and neither is a setter that reads its own getter — only a setter
that assigns `self.x`, or a getter that returns `self.x`.

The compiler cannot catch this: dot syntax is a dynamic objc_msgSend, so
-Winfinite-recursion never fires.
"""
import re, sys, pathlib

roots = sys.argv[1:]
props = {}  # selector -> (property name, header)

for root in roots:
    for h in pathlib.Path(root).rglob('*.h'):
        for line in h.read_text(errors='ignore').splitlines():
            if '@property' not in line:
                continue
            m = re.search(r'(\w+)\s*;\s*$', line)
            if not m:
                continue
            name = m.group(1)
            attrs = re.search(r'@property\s*\(([^)]*)\)', line)
            getter, setter = name, 'set' + name[0].upper() + name[1:] + ':'
            if attrs:
                a = attrs.group(1)
                g = re.search(r'getter\s*=\s*(\w+)', a)
                s = re.search(r'setter\s*=\s*(\w+:)', a)
                if g: getter = g.group(1)
                if s: setter = s.group(1)
                if 'readonly' in a: setter = None
            props[getter] = (name, h.name)
            if setter: props[setter] = (name, h.name)

# Method definition plus its body, up to the next top-level method or @end.
method_re = re.compile(
    r'^-\s*\([^)]*\)\s*(\w+:?)(.*?)(?=^\s*[-+]\s*\(|^@end)', re.M | re.S)

findings = 0
for root in roots:
    for m_file in pathlib.Path(root).rglob('*.m'):
        text = m_file.read_text(errors='ignore')
        for match in method_re.finditer(text):
            sel, body = match.group(1), match.group(2)
            if sel not in props:
                continue
            prop, header = props[sel]
            # A setter only recurses if it *assigns* self.x; reading the getter
            # from a setter (or writing the ivar) is the normal, correct shape.
            if sel.endswith(':'):
                pattern = r'\bself\.' + re.escape(prop) + r'\s*=(?!=)'
            else:
                pattern = r'\breturn\s+self\.' + re.escape(prop) + r'\b'
            if not re.search(pattern, body):
                continue
            line = text[:match.start()].count('\n') + 1
            print(f'RECURSION {m_file}:{line}: `{sel}` overrides the accessor '
                  f'for @property `{prop}` ({header}) and its body uses '
                  f'`self.{prop}` — it calls itself')
            findings += 1

print(f'{findings} self-recursive accessor(s)')
sys.exit(1 if findings else 0)
