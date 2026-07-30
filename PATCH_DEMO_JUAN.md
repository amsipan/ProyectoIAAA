# Demo predict — arquitectura v2

Modelo final: LSTM → Dropout → Dense (`2.weight`/`2.bias`). `demo_fantasma_predict.pl` debe armar la misma pila; auto-detecta `2.weight` (v2) vs `1.weight` (v1) al cargar el `.params`.
