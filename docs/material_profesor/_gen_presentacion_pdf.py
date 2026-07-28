"""Regenerate PRESENTACION_FINAL_ML.pdf — monochrome editorial 9-slide 16:9 deck."""
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor

OUT = r"C:\Users\bryan\ia\proyecto_iaaa\Proyecto\ProyectoIAAA\docs\material_profesor\PRESENTACION_FINAL_ML.pdf"
W, H = 1280, 720

ink = HexColor("#161616")
ink2 = HexColor("#3d3d3d")
ink3 = HexColor("#6b6b6b")
paper = HexColor("#fbfbf9")
hair = HexColor("#d9d9d4")
white = HexColor("#fbfbf9")

c = canvas.Canvas(OUT, pagesize=(W, H))

M = 64  # margin


def bg():
    c.setFillColor(paper)
    c.rect(0, 0, W, H, fill=1, stroke=0)


def masthead(kicker, num, dark=False):
    # Solo número de página (sin encabezado)
    fg = ink3 if not dark else HexColor("#9a9a90")
    c.setFillColor(fg)
    c.setFont("Courier", 9)
    c.drawRightString(W - M, 36, num)


def pageno(num, dark=False):
    fg = ink3 if not dark else HexColor("#8a8a80")
    c.setFillColor(fg)
    c.setFont("Courier", 9)
    c.drawRightString(W - M, 36, num)


def title(txt, y=H - 108, size=33, color=ink):
    c.setFillColor(color)
    c.setFont("Helvetica-Bold", size)
    c.drawString(M, y, txt)


def wrap(txt, x, y, font="Helvetica", size=13.5, color=ink2, maxw=1000, leading=21):
    c.setFillColor(color)
    c.setFont(font, size)
    words = txt.split()
    lines, cur = [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if c.stringWidth(t, font, size) < maxw:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    for i, ln in enumerate(lines):
        c.drawString(x, y - i * leading, ln)
    return y - len(lines) * leading


def rulehead(x, y, txt):
    c.setStrokeColor(ink)
    c.setLineWidth(2)
    c.line(x, y, x + 330, y)
    c.setFillColor(ink3)
    c.setFont("Helvetica-Bold", 8.5)
    c.drawString(x, y - 18, txt.upper())
    return y - 26


def stat(x, y, v, k_lines):
    c.setStrokeColor(ink)
    c.setLineWidth(3)
    c.line(x, y, x + 250, y)
    c.setFillColor(ink)
    c.setFont("Helvetica-Bold", 40)
    c.drawString(x, y - 46, v)
    c.setFillColor(ink2)
    c.setFont("Helvetica", 10.5)
    yy = y - 66
    for ln in k_lines:
        c.drawString(x, yy, ln)
        yy -= 14


def footer(left, right=""):
    # Sin pies de página en las diapositivas
    pass


def table(x, y, w, headers, rows, caption, colw=None, row_h=42, head_h=40):
    ncols = len(headers)
    if colw is None:
        colw = [w * 0.34] + [(w * 0.66) / (ncols - 1)] * (ncols - 1)
    c.setFillColor(ink3)
    c.setFont("Helvetica-Bold", 8.5)
    c.drawString(x, y, caption.upper())
    top = y - 14
    # header rule
    c.setStrokeColor(ink)
    c.setLineWidth(2)
    c.line(x, top, x + w, top)
    hy = top - head_h
    c.setFillColor(ink)
    c.setFont("Helvetica-Bold", 10)
    xx = x
    for i, hname in enumerate(headers):
        if i == 0:
            c.drawString(xx + 6, hy + head_h / 2 - 4, hname)
        else:
            c.drawRightString(xx + colw[i] - 6, hy + head_h / 2 - 4, hname)
        xx += colw[i]
    c.line(x, hy, x + w, hy)
    # rows
    c.setFont("Courier", 12.5)
    yy = hy
    for row in rows:
        yy -= row_h
        c.setStrokeColor(hair)
        c.setLineWidth(1)
        xx = x
        for i, val in enumerate(row):
            if i == 0:
                c.setFillColor(ink)
                c.setFont("Helvetica", 13)
                c.drawString(xx + 6, yy + row_h / 2 - 5, val)
            else:
                c.setFillColor(ink2)
                c.setFont("Courier", 12.5)
                c.drawRightString(xx + colw[i] - 6, yy + row_h / 2 - 5, val)
            xx += colw[i]
        c.line(x, yy, x + w, yy)
    c.setStrokeColor(ink)
    c.setLineWidth(2)
    c.line(x, yy, x + w, yy)
    return yy


# ---------- 01 Portada ----------
bg()
c.setStrokeColor(ink)
c.setLineWidth(3)
c.line(M, H - 90, W - M, H - 90)
title("Inteligencia Artificial y", H - 150, 40)
title("Aprendizaje Automático", H - 200, 40)
title("Proyecto Final", H - 265, 46)
wrap(
    "Predicción del comportamiento del fantasma con un modelo LSTM, a partir de la estructura "
    "y la liquidez del motor de charting.",
    M, H - 330, size=14, maxw=900, leading=23,
)
stat(M, 320, "7 649", ["muestras de entrenamiento", "(abril-junio)"])
stat(M + 300, 320, "2 391", ["muestras de prueba", "(1-24 de julio)"])
stat(M + 600, 320, "86", ["variables de entrada", "normalizadas"])
stat(M + 900, 320, "4", ["salidas numéricas", "y3 · y5 · y10 · y15"])
pageno("01")
c.showPage()

# ---------- 02 Objetivo ----------
bg()
pageno("02")
title("Cuatro salidas, una por horizonte")
wrap(
    "Cada vez que el fantasma aparece o se reubica se toma una muestra. El modelo predice cuántos "
    "rastros dejará hacia adelante en cuatro horizontes distintos.",
    M, H - 155, size=13.5, maxw=1050, leading=21,
)
y0 = H - 230
labels = [
    ("y3", "rastros en los próximos 3 minutos"),
    ("y5", "rastros en los próximos 5 minutos"),
    ("y10", "rastros en los próximos 10 minutos"),
    ("y15", "rastros en los próximos 15 minutos"),
]
yy = rulehead(M, y0, "Definición de las salidas")
for lab, txt in labels:
    yy -= 40
    c.setFillColor(ink)
    c.setFont("Courier-Bold", 13)
    c.drawString(M + 4, yy + 12, lab)
    c.setFillColor(ink2)
    c.setFont("Helvetica", 13)
    c.drawString(M + 80, yy + 12, txt)
    c.setStrokeColor(hair)
    c.setLineWidth(1)
    c.line(M, yy, M + 620, yy)

xr = M + 700
yy2 = rulehead(xr, y0, "Entrada del modelo")
wrap(
    "Una ventana de 5 muestras consecutivas, cada una con 86 variables calculadas en la vela "
    "siguiente al evento: distancias en PIPs a niveles de liquidez y estructura en 1m, 10m y 1h.",
    xr, yy2 - 12, size=12.5, maxw=440, leading=19,
)
c.showPage()

# ---------- 03 Muestreo ----------
bg()
pageno("03")
title("El disparo es el evento del fantasma")
steps = [
    ("01", "Detección del evento", "Se recorre el histórico 1m en modo Replay y se registra cada aparición o reubicación del fantasma provisional."),
    ("02", "Contexto causal", "Las variables se calculan mirando solo hacia atrás, con la información disponible hasta la vela siguiente al evento. Nada mira el futuro."),
    ("03", "Etiquetado automático", "Las salidas y3/y5/y10/y15 se obtienen contando los rastros que efectivamente aparecen después del evento."),
]
yy = H - 170
for num, head, body in steps:
    c.setFillColor(ink3)
    c.setFont("Courier-Bold", 11)
    c.drawString(M, yy, num)
    c.setFillColor(ink)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(M + 44, yy, head)
    wrap(body, M + 44, yy - 24, size=12.5, maxw=600, leading=19)
    yy -= 96

xr = M + 720
yy2 = rulehead(xr, H - 170, "Volumen del dataset")
rows = [
    ("Train", "7 649 muestras · abr-jun (88 736 velas)"),
    ("Test", "2 391 muestras · 1-24 jul (24 179 velas)"),
    ("Secuencias", "7 645 train / 2 387 test (ventana 5)"),
]
yy3 = yy2 - 30
for lab, txt in rows:
    c.setFillColor(ink)
    c.setFont("Courier-Bold", 11.5)
    c.drawString(xr, yy3, lab)
    c.setFillColor(ink2)
    c.setFont("Helvetica", 11.5)
    c.drawString(xr + 100, yy3, txt)
    c.setStrokeColor(hair)
    c.line(xr, yy3 - 12, xr + 490, yy3 - 12)
    yy3 -= 46
wrap(
    "El comportamiento del fantasma replica el indicador implementado en el motor de charting.",
    xr, yy3 - 14, size=10.5, color=ink3, maxw=480, leading=15,
)
c.showPage()

# ---------- 04 Proceso ----------
bg()
pageno("04")
title("Del CSV al modelo")
cards = [
    ("1 · EXTRACCIÓN", "Script sin interfaz gráfica recorre el CSV en Replay y, en cada evento del fantasma, guarda una fila con las 86 variables y las 4 salidas futuras.", "7 649 filas train · 2 391 test"),
    ("2 · NORMALIZACIÓN", "Estandarización z-score con media y desviación calculadas solo con train; el test se transforma con los mismos parámetros.", "Tiempo y metadatos no entrenan"),
    ("3 · ENTRENAMIENTO", "LSTM de una capa (48 unidades, dropout 0.2), ventana de 5 muestras, 4 salidas, error cuadrático medio, optimizador Adam y parada temprana con validación.", "Grid de 8 configuraciones (~8 min) · pesos guardados en disco"),
]
for i, (head, body, note) in enumerate(cards):
    x = M + i * 400
    yy = rulehead(x, H - 165, head)
    wrap(body, x, yy - 16, size=12, maxw=355, leading=18)
    c.setFillColor(ink3)
    c.setFont("Helvetica", 10)
    c.drawString(x, 210 - i * 0 + 30, note)
c.showPage()

# ---------- 05 Regresión ----------
bg()
pageno("05")
title("Error en el conteo de rastros")
table(
    M, H - 160, 560,
    ["Salida", "MAE", "RMSE"],
    [
        ("y3 · 3 min", "0.82", "1.01"),
        ("y5 · 5 min", "1.15", "1.41"),
        ("y10 · 10 min", "1.75", "2.15"),
        ("y15 · 15 min", "2.24", "2.77"),
    ],
    "Regresión · n = 2 387 secuencias de test",
)
wrap(
    "En la ventana corta el modelo se equivoca en menos de un rastro en promedio (MAE 0.82 en y3). "
    "El error crece con el horizonte, de forma esperada: a 15 minutos hay más rastros posibles y más incertidumbre. "
    "El error medio de las cuatro ventanas es 1.49 rastros, un 17% menos que la primera versión entrenada del modelo.",
    M + 640, H - 200, size=13, maxw=500, leading=21,
)
c.showPage()

# ---------- 06 Binaria ----------
bg()
pageno("06")
title("¿Aparece al menos un rastro?")
table(
    M, H - 160, 700,
    ["Salida", "Accuracy", "Precision", "Recall", "F1"],
    [
        ("y3", "0.71", "0.69", "0.98", "0.81"),
        ("y5", "0.75", "0.75", "0.99", "0.85"),
        ("y10", "0.81", "0.81", "0.99", "0.89"),
        ("y15", "0.83", "0.84", "0.99", "0.91"),
    ],
    "Positivo = ≥1 rastro en la ventana · n = 2 387",
)
wrap(
    "El modelo casi no se pierde una ventana con actividad: detecta 98-99% de los casos con al "
    "menos un rastro (recall). Cuando anuncia actividad a 10-15 minutos acierta 81-84% de las veces "
    "(precision); el F1 promedio de las cuatro ventanas es 0.87.",
    M + 770, H - 200, size=13, maxw=380, leading=21,
)
c.showPage()

# ---------- 07 Confusión ----------
bg()
pageno("07")
title("Detalle por ventana")
table(
    M, H - 160, 700,
    ["Salida", "TP", "FP", "TN", "FN"],
    [
        ("y3", "1 513", "668", "174", "32"),
        ("y5", "1 675", "563", "126", "23"),
        ("y10", "1 862", "427", "81", "17"),
        ("y15", "1 939", "380", "46", "22"),
    ],
    "Positivo = ≥1 rastro · n = 2 387 por fila",
)
xr = M + 770
yy = rulehead(xr, H - 165, "Lectura")
defs = [
    ("TP", "predijo rastro y sí hubo"),
    ("FP", "predijo rastro y no hubo"),
    ("TN", "predijo que no y no hubo"),
    ("FN", "predijo que no y sí hubo"),
]
yy -= 20
for lab, txt in defs:
    c.setFillColor(ink)
    c.setFont("Courier-Bold", 12)
    c.drawString(xr, yy, lab)
    c.setFillColor(ink2)
    c.setFont("Helvetica", 12)
    c.drawString(xr + 44, yy, txt)
    yy -= 30
wrap(
    "Casi no deja pasar actividad real: solo 17-32 falsos negativos por ventana, "
    "de 1 545-1 961 casos con rastro.",
    xr, yy - 12, size=10.5, color=ink3, maxw=380, leading=15,
)
c.showPage()

# ---------- 08 Demo ----------
bg()
pageno("08")
title("Cargar el modelo y comparar")
wrap(
    "El programa carga los pesos entrenados (no reentrena), arma las ventanas de 5 muestras sobre el "
    "test ya normalizado e imprime el conteo real contra la predicción para varios puntos de julio.",
    M, H - 155, size=13.5, maxw=1050, leading=21,
)
# command box
c.setFillColor(ink)
c.roundRect(M, H - 320, W - 2 * M, 110, 6, fill=1, stroke=0)
c.setFillColor(HexColor("#8a8a80"))
c.setFont("Courier", 11)
c.drawString(M + 20, H - 245, "# entorno: WSL Fedora - raiz del proyecto")
c.setFillColor(white)
c.setFont("Courier-Bold", 13)
c.drawString(M + 20, H - 272, "cd /mnt/c/Users/bryan/ia/proyecto_iaaa/Proyecto/ProyectoIAAA")
c.drawString(M + 20, H - 296, "perl -I. scripts/demo_fantasma_predict.pl --n 8")
cols = [
    ("PASO 1", "Carga el test normalizado y los pesos .params"),
    ("PASO 2", "Construye ventanas de 5 muestras consecutivas"),
    ("PASO 3", "Imprime TRUE vs PRED para y3 · y5 · y10 · y15"),
]
for i, (head, body) in enumerate(cols):
    x = M + i * 400
    yy = rulehead(x, H - 360, head)
    wrap(body, x, yy - 14, size=12, maxw=355, leading=18)
c.showPage()

# ---------- 09 Cierre (dark) ----------
c.setFillColor(ink)
c.rect(0, 0, W, H, fill=1, stroke=0)
pageno("09", dark=True)
title("Qué queda demostrado", H - 108, 33, white)
items = [
    ("01", "El disparo es correcto", "Cada muestra corresponde a un evento real del fantasma, con contexto estrictamente causal."),
    ("02", "El pipeline es reproducible", "Extracción, normalización, entrenamiento y evaluación quedan como scripts ejecutables."),
    ("03", "El modelo predice en vivo", "Carga los pesos y compara contra datos que nunca vio en entrenamiento."),
]
yy = H - 170
for num, head, body in items:
    c.setFillColor(HexColor("#9a9a90"))
    c.setFont("Courier-Bold", 11)
    c.drawString(M, yy, num)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(M + 44, yy, head)
    wrap(body, M + 44, yy - 24, size=12.5, color=HexColor("#c9c9c0"), maxw=600, leading=19)
    yy -= 92

# summary table dark
xr = M + 720
c.setFillColor(HexColor("#9a9a90"))
c.setFont("Helvetica-Bold", 8.5)
c.drawString(xr, H - 160, "RESUMEN")
c.setStrokeColor(white)
c.setLineWidth(2)
c.line(xr, H - 170, xr + 490, H - 170)
rows = [
    ("Dataset train/test", "7 649 / 2 391"),
    ("Variables", "86"),
    ("MAE prom · 4 ventanas", "1.49"),
    ("F1 prom · binario", "0.87"),
]
yy = H - 210
for lab, val in rows:
    c.setFillColor(white)
    c.setFont("Helvetica", 13)
    c.drawString(xr, yy, lab)
    c.setFont("Courier", 13)
    c.drawRightString(xr + 490, yy, val)
    c.setStrokeColor(HexColor("#3d3d3d"))
    c.setLineWidth(1)
    c.line(xr, yy - 14, xr + 490, yy - 14)
    yy -= 42

c.setFillColor(HexColor("#9a9a90"))
c.setFont("Helvetica", 8.5)
c.drawString(M, 36, "Gracias · preguntas")
c.drawRightString(W - M, 36, "Material de apoyo: guion de exposición y checklist de demo")
c.showPage()

c.save()
print("Wrote", OUT)
