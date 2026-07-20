# Manifiesto del corpus actualizado — julio de 2026

**Propósito.** Este directorio conserva la evidencia usada para determinar los requisitos actuales de la aplicación. Los outputs del ASR se preservan sin correcciones silenciosas. Son resultados automáticos reproducibles, **no transcripciones literales certificadas**.

## Regla de precedencia

1. Solo se comparan afirmaciones referidas al mismo requisito.
2. Una instrucción explícita posterior del profesor reemplaza a la anterior.
3. Una aclaración posterior compatible se integra, no elimina la regla previa.
4. Una omisión posterior no equivale a cancelación.
5. La imagen confirma inventario y relaciones generales, pero no crea parámetros algorítmicos.
6. Las preguntas o comentarios de estudiantes no se tratan como instrucciones del profesor.
7. El código demuestra el estado de la app, no la intención del profesor.
8. Una decisión técnica razonable se etiqueta como tal y no se atribuye al profesor.

## Orden temporal de los audios

| Orden | Fecha local atribuida | Fuente original | Duración | SHA-256 original |
|---:|---|---|---:|---|
| 1 | 2026-07-07 18:03:49 | `WhatsApp Ptt 2026-07-07 at 6.03.49 PM.ogg` | 1713.5465 s | `E687401E6F9D351E23ADF605262B226F3F9AE567D14AFC6FC15DE559D964145E` |
| 2 | 2026-07-14 16:48:09 | `WhatsApp Ptt 2026-07-14 at 4.48.09 PM.ogg` | 569.8265 s | `32B665A21F230781DDD9C8D8FFCD6FDBA5C2EC93A408598CB0ACA90BA5980C8C` |
| 3 | 2026-07-14 17:35:24 | `WhatsApp Ptt 2026-07-14 at 5.35.24 PM.ogg` | 2832.2665 s | `3DA0E05F58BA09F7E7B17B4ACD674A3EA766CDC643211A7CE4A73B116E0FA534` |
| 4 | 2026-07-15 17:55:29 (UTC−5) | `Inteligencia Artificial (IndicacionesExaProy).m4a` | 1606.524229 s | `FDBCE931F67F2F974913EF7C662CB0D868E1EBAA0869361846BF14459EB34D68` |

La fecha del M4A proviene del metadata embebido `2026-07-15T22:55:29Z`. Los OGG no tienen fecha embebida útil y usan su fecha nominal. Las fechas de Windows corresponden a la descarga, no a la grabación.

## Transcripción por OpenClaw

- Helper: `/home/openclaw/.openclaw/scripts/long-audio-transcribe.py`
- Modelo: `whisper-large-v3-turbo`
- Idioma: español

| Audio | Resultado remoto | Chunks | Archivos canónicos |
|---|---|---:|---|
| 07-jul | `ptt_20260707_180349-20260719-224602` | 2 | `2026-07-07_180349_whatsapp_ptt.{raw.txt,chunked.md,metadata.json}` |
| 14-jul 16:48 | `ptt_20260714_164809-20260719-224628` | 1 | `2026-07-14_164809_whatsapp_ptt.{raw.txt,chunked.md,metadata.json}` |
| 14-jul 17:35 | `ptt_20260714_173524-20260719-224635` | 3 | `2026-07-14_173524_whatsapp_ptt.{raw.txt,chunked.md,metadata.json}` |
| 15-jul | `IA_IndicacionesExaProy-20260719-051032` | 2 | `2026-07-15_175529_indicaciones_exaproy.{raw.txt,chunked.md,metadata.json}` |

`raw.txt` conserva sin editar el output consolidado del ASR. `chunked.md` añade únicamente IDs `[0001]`, `[0002]`, etc. Los directorios `ptt_*` preservan el resultado remoto de los tres OGG. El M4A conserva output y metadata canónicos, pero no una copia del directorio remoto completo. El paquete `ptt_transcripts_20260719.tar.gz` coincide local/remoto con SHA-256 `61C4798C780A3535758843C77B873AEE6F3282788E461D61385B222E2CFBC778`.

### Limitación crítica del ASR

A07 y A14b contienen frases como `Preserve names, class topics, and technical terms` y `Preserve names, and then return`. Son inserciones del prompt/pipeline de transcripción, no afirmaciones del profesor. Se preservan para mantener inmutable la evidencia, pero se excluyen del análisis. La proximidad de una cita a esas inserciones reduce su confianza. Además, no existe diarización ni timestamp por oración, por lo que preguntas de estudiantes y respuestas del profesor se separan por contexto, no por una identificación automática segura.

## Hashes de outputs canónicos

| Archivo | SHA-256 |
|---|---|
| `2026-07-07_180349_whatsapp_ptt.raw.txt` | `3F455813060A5483C43C46442FF6E89EFBC9C898737CE7F7D50AFB9D153739B8` |
| `2026-07-07_180349_whatsapp_ptt.chunked.md` | `B75CA08EE7A3DD5B3A89D5362B2A6391E9D06696E6BE6D4403FAD4E1D98D2B3A` |
| `2026-07-14_164809_whatsapp_ptt.raw.txt` | `C34E395FC202DE5152DDA7A0A38C394F0BEA9581D17237A8EA82BE4FD5483CD0` |
| `2026-07-14_164809_whatsapp_ptt.chunked.md` | `1E9381335C522FE5C343179F4A9057DEBAE0C87E8F90AD973F6BE2DFA0007A92` |
| `2026-07-14_173524_whatsapp_ptt.raw.txt` | `0F53744EFC383C502B0E96E7BE58959B069FCCD8FEC289F9D47FEBD6E2C38947` |
| `2026-07-14_173524_whatsapp_ptt.chunked.md` | `4F45C3AFF81C175CB77B0C4F0EA38D32BC74A845B22717936135DD9BCD1AB3C2` |
| `2026-07-15_175529_indicaciones_exaproy.raw.txt` | `EC6517BCD28D56F0B18987A8A7DD5EFA7D9171F1639C8EC525086F3FB37F261C` |
| `2026-07-15_175529_indicaciones_exaproy.chunked.md` | `893E1EA98CA7B82B574EE9E81B1D5B957FCA918FD28DF6DC8E944BD07B5DD917` |

## Imagen

| Archivo | Dimensiones | SHA-256 | Método |
|---|---:|---|---|
| `indicadores_resumen_202607.png` | 1600×1200 | `F309D27006DD01231CD728C5B73C5A37016D630E6C383AC6B0F6DE021C6029B1` | inspección visual + OCR local multipasada |

El OCR se ejecutó localmente con `rapidocr==3.9.1` y `onnxruntime==1.27.0` en un entorno temporal. No se transmitió la imagen ni se modificaron dependencias del proyecto. Los JSON OCR son ayudas, no fuentes normativas.

## Fuentes complementarias preservadas

- PDF contractual: `../Especificacion_Proyeto_2a_Fase.pdf`
- Texto PDF: `../Especificacion_2a_Fase_TEXTO.txt`
- Contrato técnico: `../../PHASE2_DEBUG_CONTRACT.md`
- Lumina SMC: `lumina/a21ce910fecc_smc.raw.txt`, SHA-256 `B22990BA289AD6BF33193D3CA0D66D738EEF34148887092679ED4FE7612F88DF`
- Lumina Liquidity/HMM: `lumina/1d3e610b36ae_liquidity_hmm.raw.txt`, SHA-256 `6D7687E43BADD673A1287CD76340CC0BC9C1B2F626176DABAB1975BD86A675A1`
- Lumina indicadores: `lumina/47bfe676f0e6_indicadores.raw.txt`, SHA-256 `8F9149712B1D7CE2A88964E27E60EAEB95AB127014FB880CC3696B3E6CD57149`

Las fechas de importación de Lumina pueden diferir de la fecha nominal de clase. Se consideran fuentes anteriores a julio.

## Artefactos de decisión

- `CHECKLIST_ACEPTACION_IMAGEN.md`: texto exacto proporcionado por Bryan, estado contra runtime y orden de cierre visual.
- `TRANSCRIPCION_IMAGEN_INDICADORES.md`: inventario visual corregido y límites de lectura. La transcripción humana exacta del 20-07-2026 prevalece sobre el OCR.
- `MATRIZ_REQUISITOS_ACTUALIZADOS.md`: cronología, conflictos y nivel de evidencia.
- `REQUISITOS_VIGENTES_PROFESOR.md`: dictamen consolidado y decisiones técnicas abiertas.

## Trazabilidad de la investigación

La sesión histórica es `019f7b74-0bb6-73c3-bdd4-eeb24c8e7877`. Sus rutas absolutas bajo `.grok/sessions/...C%3A%5Cm1...` son solo trazabilidad histórica de la conversación y **no** convierten `C:\m1` en repositorio canónico. El proyecto canónico continúa en `C:\ia\proyecto_iaaa\Proyecto\ProyectoIAAA`.

## Límites de confianza

No hay diarización ni timestamps por oración. Errores como “SMS Pro”, “Disney”, “GMN”, “view up” y “graph” se interpretan por contexto como SMC Pro, t-SNE, GMM, VWAP y Grab. Los parámetros no pronunciados quedan abiertos. Para una disputa sobre una frase sensible deberá escucharse el intervalo del audio original, porque el texto automático por chunks no basta como cita literal certificada.
