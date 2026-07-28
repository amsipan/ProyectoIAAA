import re

src_path = r'C:\Users\bryan\ia\proyecto_iaaa\Proyecto\ProyectoIAAA\docs\material_profesor\_gen_presentacion_pdf.py'
with open(src_path, encoding='utf-8') as f:
    src = f.read()

src = re.sub(r'footer\([^)]*\)\n', '', src)


def repl(m):
    num = m.group(1)
    dark = ', dark=True' if m.group(2) else ''
    return f'pageno("{num}"{dark})'


src = re.sub(r'masthead\("[^"]*",\s*"(\d+)"(,\s*dark=True)?\)', repl, src)

with open(src_path, 'w', encoding='utf-8') as f:
    f.write(src)
print('patched')
