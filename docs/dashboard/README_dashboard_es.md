# Power BI Dashboard — Monitor de Anomalías de Ausentismo

> Parte de [`ai-hr-absenteeism-anomaly`](https://github.com/AlonsoMaurer/ai-hr-absenteeism-anomaly) · Ubicado en `docs/dashboard/`

Dashboard interactivo de Power BI construido sobre `analytics.anomaly_alerts`. Diseñado para uso diario de HRBPs: revisar alertas de anomalías priorizadas por departamento y turno, filtradas por severidad y z-score.

**Archivos en esta carpeta:**
- `Dashboard3.pbix` — archivo de reporte Power BI
- `HR_Anomaly_Dark_Theme.json` — tema oscuro personalizado (importar desde Ver → Temas)

---

## 1) Qué muestra el dashboard

El dashboard responde la misma pregunta de negocio que el pipeline:

> *¿Qué combinaciones de departamento + turno muestran ausentismo anómalo hoy en comparación con su propia línea base de 28 días — y qué tan severa es la desviación?*

Lo presenta en cinco visualizaciones:

| Visual | Qué muestra |
|---|---|
| Tarjetas KPI | Total de anomalías, cantidad de alta severidad, tasa promedio de ausentismo, departamentos afectados — todas responden al filtro de turno |
| Anomalías por depto (barras) | Conteo total de anomalías por departamento, orden descendente |
| Heatmap depto × turno (matriz) | Conteo de anomalías por celda depto-turno; intensidad de color = frecuencia |
| Tendencia diaria (línea) | Conteo de anomalías por día en los últimos 30 días |
| Tabla de alertas | Una fila por departamento — peor anomalía, ordenada por z-score desc; pills de severidad con código de color |

---

## 2) Fuente de datos

**Tabla:** `analytics.anomaly_alerts` (BigQuery, importada en modo Import de Power BI)

| Columna | Tipo | Descripción |
|---|---|---|
| `date` | Fecha | Fecha de observación |
| `department_id` | Entero | Identificador de departamento |
| `shift_id` | Entero | Turno (1, 2, 3) |
| `scheduled_headcount` | Entero | Headcount planificado para el día |
| `absent_headcount` | Entero | Empleados ausentes |
| `absence_rate` | Decimal | `ausentes / planificados` |
| `mean_28d` | Decimal | Media móvil de tasa de ausentismo (28 días) |
| `std_28d` | Decimal | Desviación estándar móvil (28 días) |
| `z_score` | Decimal | `(absence_rate - mean_28d) / std_28d` |
| `is_anomaly` | Entero | 1 si fue flaggeado, 0 en caso contrario |
| `alert_severity` | String | High / Medium / Low / Normal |

**Conexión:** BigQuery → Power BI Desktop, modo Import. El refresh es manual en el MVP; el refresh programado requeriría Power BI Service.

---

## 3) Medidas DAX

Las medidas están organizadas en carpetas de visualización dentro del modelo.

### KPIs principales
| Medida | Descripción |
|---|---|
| `Total Anomalies` | `COUNT` donde `is_anomaly = 1` |
| `High Severity` | `COUNT` donde `alert_severity = "High"` e `is_anomaly = 1` |
| `Avg Absence Rate Anomalies` | `AVERAGE(absence_rate)` para filas anómalas |
| `Depts Affected` | `DISTINCTCOUNT(department_id)` donde `is_anomaly = 1` |
| `Daily Anomaly Count` | Conteo de anomalías por día |

### Filtros (con contexto de turno)
| Medida | Descripción |
|---|---|
| `Total Anomalies (Filtered)` | Respeta el contexto del slicer de turno |
| `High Severity (Filtered)` | Respeta el contexto del slicer de turno |
| `Avg Absence Rate (Filtered)` | Respeta el contexto del slicer de turno |
| `Depts Affected (Filtered)` | Respeta el contexto del slicer de turno |
| `Selected Shift Label` | Devuelve "Shift 1 / 2 / 3" o "All Shifts" |

### Severidad (formato condicional)
| Medida | Descripción |
|---|---|
| `Severity Color` | Color hex por nivel de severidad — usado para binding de fuente/relleno |
| `Severity Font Color` | Variante clara (`#FCA5A5 / #FDBA74 / #86EFAC`) para texto de pills |
| `Severity Background Color` | Variante oscura (`#3B0F0F / #3B1F0A / #0A2E1A`) para relleno de pills |
| `Severity Label` | `⬤ High / ⬤ Medium / ⬤ Low` — devuelve `BLANK()` en la fila de totales |
| `Absence Rate Color` | Color semántico vinculado a la columna `absence_rate` |

### Tabla de alertas (agregada por depto)
| Medida | Descripción |
|---|---|
| `Max Z-Score` | Peor z-score por departamento |
| `Max Absence Rate` | Tasa de ausentismo más alta por departamento |
| `Max Absence Rate Color` | Color semántico para la columna `Max Absence Rate` |
| `Max Headcount` | Headcount en la peor anomalía |
| `Top Severity Label` | Pill de severidad para la peor anomalía por departamento |
| `Top Severity Font Color` | Color de fuente para `Top Severity Label` |
| `Avg Baseline 28d` | Promedio de la línea base de 28 días por departamento |

---

## 4) Decisiones de ingeniería

### A) Simulación de pills mediante medida de texto
Los visuals de tabla en Power BI aplican el color de fondo condicional a la **fila completa**, no a celdas individuales. Esto hacía que las pills de severidad se expandieran por todas las columnas, rompiendo la jerarquía visual.

**Decisión:** `Severity Label` usa el símbolo Unicode `⬤` con color de fuente condicional (`Severity Font Color`) para simular pills sin artefactos de fondo por fila. El trade-off es que la pill es solo texto — sin celda con fondo relleno.

### B) Agregación por departamento en la tabla de alertas
La tabla subyacente tiene una fila por depto-turno-día. Mostrarla en crudo produce decenas de filas con duplicados por departamento.

**Decisión:** la tabla de alertas agrega a una fila por departamento usando `Max Z-Score`, `Max Absence Rate` y `Top Severity Label` — mostrando la peor anomalía por depto. El trade-off es la pérdida del detalle por turno en esta vista; el heatmap cubre ese ángulo.

### C) Número de día en el eje de tendencia
El dataset sintético abarca un período histórico fijo (no rolling desde hoy). Usar fechas de calendario en el eje producía un gráfico confuso con meses de 2024–2025.

**Decisión:** usar `Día` (número de día 1–30) en el eje X con el título "Daily Anomaly Trend — Last 30 Days". Esto mantiene el encuadre consistente independientemente de cuándo se abra el archivo. El trade-off es la pérdida de referencias a fechas específicas.

### D) Modo Import (no DirectQuery)
El modo DirectQuery de Power BI contra BigQuery introduce latencia en cada interacción con los visuales.

**Decisión:** modo Import con refresh manual para el MVP. Aceptable dado el ciclo de actualización diaria de `analytics.anomaly_alerts`. El despliegue en producción usaría refresh programado vía Power BI Service.

### E) Nombres de departamento en blanco
Los registros asociados a IDs de departamento deduplicados (2 y 9 — ver README principal, Sección 5E) producen filas sin coincidencia en el join de Power BI.

**Decisión:** filtrados a nivel de visualización mediante `department_name is not blank`. Esto es consistente con el manejo documentado en el README principal del pipeline. La solución permanente (remapeo de IDs en SQL) es una mejora futura documentada.

---

## 5) Tema visual

Aplicado mediante `HR_Anomaly_Dark_Theme.json` (Ver → Temas → Examinar temas).

| Token | Hex | Uso |
|---|---|---|
| Fondo del canvas | `#0F1117` | Fondo de página (configurar manualmente — no controlable vía JSON de tema) |
| Superficie | `#181C27` | Fondos de visuales |
| Superficie 2 | `#1F2535` | Filas alternas, celdas vacías del heatmap |
| Borde | `#2A3147` | Bordes de visuales, líneas de cuadrícula |
| Texto principal | `#FFFFFF` | Valores KPI |
| Texto secundario | `#64748B` | Etiquetas, subtítulos, texto de ejes |
| Alta severidad | `#EF4444` | Color de anomalía alta |
| Media severidad | `#F97316` | Color de anomalía media |
| Baja severidad | `#22C55E` | Color de anomalía baja |
| Acento | `#3B82F6` | Color de datos por defecto, tile activo del slicer |

**Limitación conocida:** el JSON de tema de Power BI no soporta `transparent` como valor de color. El fondo del canvas (`#0F1117`) debe configurarse manualmente desde Ver → Fondo de página.
