import re

p = r'C:\Users\bryan\ia\proyecto_iaaa\Proyecto\ProyectoIAAA\docs\material_profesor\PRESENTACION_FINAL_ML.html'
with open(p, encoding='utf-8') as f:
    html = f.read()

# 1) Capture slide numbers from mastheads, then remove masthead blocks
def masthead_num(m):
    return m.group(1)

# store mapping slide -> num in order
nums = re.findall(r'<span class="num">(\d+)</span>', html)
# remove mastheads
html = re.sub(r'<div class="masthead">.*?</div>\s*', '', html, flags=re.S)

# 2) Remove footer blocks entirely (their text), keep structure minimal
html = re.sub(r'<div class="footer".*?</div>\s*', '', html, flags=re.S)

# 3) Add a minimal page number to each non-cover slide
slide_parts = re.split(r'(<section class="slide[^"]*" data-title="[^"]*">)', html)
out = []
slide_idx = 0
for i, part in enumerate(slide_parts):
    out.append(part)
    if re.match(r'<section class="slide', part) and 'data-title="Portada"' not in part:
        slide_idx += 1
        # number = slide_idx + 1 (cover is 01)
        num = f'{slide_idx + 1:02d}'
        # find closing </section> for this slide and insert number before it
        # handled in next content part

# Simpler: rebuild by locating each </section> and adding number to preceding slide
# Redo from original with mastheads removed:
with open(p, encoding='utf-8') as f:
    html = f.read()
html = re.sub(r'<div class="masthead">.*?</div>\s*', '', html, flags=re.S)
html = re.sub(r'<div class="footer".*?</div>\s*', '', html, flags=re.S)

# Insert page number before each </section> except the first (cover already has 01)
sections = html.split('</section>')
res = []
count = 0
for i, sec in enumerate(sections):
    if '<section class="slide' in sec and 'data-title="Portada"' not in sec:
        count += 1
        num = f'{count + 1:02d}'
        sec = sec + f'<span class="pagenum">{num}</span>'
    res.append(sec)
html = '</section>'.join(res)

# cover slide: ensure number 01 style matches
html = html.replace('<div class="footer" style="justify-content:flex-end"><span>01</span></div>',
                    '<span class="pagenum">01</span>')

# Add pagenum CSS
html = html.replace('.chrome {',
                    '.pagenum {\n      position: absolute;\n      right: 1.6rem;\n      bottom: 1rem;\n      font-family: "JetBrains Mono", monospace;\n      font-size: 0.78rem;\n      color: var(--ink-3);\n    }\n    .dark .pagenum { color: #8a8a80; }\n\n    .chrome {')

with open(p, 'w', encoding='utf-8') as f:
    f.write(html)
print('slides numbered:', count + 1)
