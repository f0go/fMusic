# Verificación de mezcla musical — 14/11/2026

Dispositivo: iPhone 14 Pro del usuario, iOS 27.2. Audio: cuatro MP3 reales de la caché existente de la app. No se incluyen archivos musicales ni credenciales en el repositorio.

Se ejecutaron en el dispositivo tres transiciones con decodificación y renderizado reales, ajuste de tempo sin cambio de tono e intercambio gradual de graves:

| Transición | Mezcla audible | Velocidad entrante | Salida de la primera pista | Duración original |
|---|---:|---:|---:|---:|
| Todas Mueren por Mí → Shorty Party | 10,48 s | 95,83 % | 212,87 s | 223,09 s |
| Burbujas de Cristal → Los Mensajes del Whatsapp | 7,81 s | 95,35 % | 217,58 s | 224,60 s |
| Shorty Party → Los Mensajes del Whatsapp | 1,28 s | 100 % | 260,14 s | 265,01 s |

La tercera pareja tiene tempos incompatibles para un ajuste moderado (96 y 129 BPM): usa un enlace rítmico corto en vez de superponer baterías desincronizadas. La entrada de Los Mensajes del Whatsapp se eligió alrededor del segundo 7,48, no al comienzo del archivo.

Las pruebas verificaron promoción antes del final, posición de entrada, tiempo audible de superposición y ausencia de errores del motor. Esto verifica ejecución y tiempos; no sustituye la valoración auditiva del usuario.

28 pruebas pasaron en el iPhone, incluida la aceptación con canciones reales. El probe temporal que leía la caché privada se retiró del proyecto después de la prueba. Permanecen los tests portables del detector, planificador, persistencia y transporte.

La UI se ejecutó y revisó en simulador con tamaño de texto normal y accesibilidad XXXL. El cuarto botón de la cola activa/desactiva la misma preferencia persistida que Ajustes. Sus etiquetas están traducidas a los nueve idiomas soportados.

Además, se descargaron los cuatro MP3 mediante HTTP desde un servidor local y se ejecutó el analizador de producción en macOS: las cuatro descargas produjeron cuadrículas de entrada y salida válidas. Esto detectó y permitió corregir la extensión del temporal, que impedía abrir el audio remoto en AVFoundation. La regresión portable renombra un WAV a un nombre opaco, lo conserva con su contenedor real y verifica su decodificación.

37 pruebas de regresión del planificador, transporte, precarga y política de álbumes pasaron en simulador.
