# Imagen y color: Hisense 40A45H

Ajustes de imagen para ver de noche con la luz apagada (de día, con luz, se ve bien igual). Se guardan
**por entrada**: lo de aquí es para las apps (YouTube, Crunchyroll, etc.); la entrada HDMI se ajusta aparte.
Si una actualización o un reinicio de fábrica los borra, se vuelven a poner con esta tabla.

Configuración → Imagen (o el botón de APPS del control, que abre la Configuración).

## Apps (verificado el 2026-10-23)

| Opción | Valor | Por qué |
| --- | --- | --- |
| Modo de imagen | Película | El modo con colores más fieles. «Ahorro de energía» (el que tenía) oscurece y pierde las sombras. |
| Retroiluminación automática | Apagar | Que no cambie la luz sola. |
| Retroiluminación | 35 | Cuánta luz da la pantalla. Es lo que se sube o se baja a gusto, sin perder detalle. |
| Brillo | 49 | Ajustado con el patrón «AVS HD 709 black clipping»: se ven parpadear las barras 17 a 25 y no las 2 a 16. **No se baja para oscurecer: para eso está la retroiluminación.** |
| Contraste | 45 | El de fábrica de Película. |
| Saturación | 45 | El de fábrica de Película. |
| Matiz | 0 | |
| Nitidez | 6 | Más alto agrega bordes falsos. |
| Temperatura de color | Cálida | Quita el azul de los blancos. Al principio se ve amarillento; es lo correcto. |
| Gamma | Media | Si las escenas oscuras siguen perdiéndose, probar «Claro». |
| Control de contraste local | Desactivado | Cambia el brillo por zonas y se come las sombras. |
| Control de Luma adaptativo | Desactivado | Cambia el brillo según la escena; pierde detalle en lo oscuro. |
| Reducción de ruido en MPEG | Desactivado | Borra detalle. |
| DNR | Desactivado | Borra detalle. |
| Modo de película DI | Automático | |
| Blue stretch | Apagado | Si se prende, azula los blancos. |
| Luz azul baja | Desactivado | La temperatura Cálida ya lo hace, y mejor. |
| Modo de juego, Modo de PC | Apagado | |
| Rango RGB para HDMI | Automático | Solo afecta a HDMI. |
| Balance de blancos de 11 puntos, Sintonizador de color | Sin tocar | Se ajustan con un medidor; a ojo se descompone. |

Valores que la TV guarda (`adb shell settings list global | grep picture_`): `picture_mode=9` (Película),
`picture_color_temperature=3` (Cálida), `picture_gamma=2` (Media), `picture_backlight=35`,
`picture_brightness=49`, `picture_contrast=45`, `picture_saturation=45`, `picture_hue=0`, `picture_sharpness=6`.
Antes de ajustar: modo 11 (Ahorro de energía), temperatura 2 (Estándar), retroiluminación 60.

## HDMI

Pendiente: repetir la tabla en la entrada HDMI con el aparato conectado. Si ahí los negros se ven grises
(lavados) o se pierden, cambiar «Rango RGB para HDMI» entre Automático, Completo y Limitado hasta que el
patrón de brillo se vea como en las apps.
