# Detección de Anomalías de Ausentismo con IA (MVP)
> 🇬🇧 [English version available here](README.md)

Proyecto de portfolio de AI Engineering end-to-end: **detección diaria de anomalías de ausentismo** por **área + turno** para HRBPs, usando **BigQuery (SQL)** + **Python** + **Power BI** + **GitHub**.

---

## Resumen ejecutivo

**Problema:** Los HR Business Partners en organizaciones medianas y grandes no cuentan con un sistema de alerta temprana para picos de ausentismo — los patrones inusuales suelen detectarse días después, cuando el impacto operacional ya ocurrió.

**Solución:** Un pipeline analítico end-to-end (BigQuery + Python + Power BI) que calcula anomalías diarias por z-score por área + turno, produciendo una tabla de alertas priorizadas para la acción del HRBP.

**Resultado:** En un dataset sintético de 3.425 empleados, el sistema identificó **103 combinaciones área-turno-día anómalas** en 6 meses de datos de asistencia — señales que habrían pasado invisibles en reportes de dotación tradicionales.

**Stack:** BigQuery · Python · Power BI · GitHub  
**Alcance:** Detección solo a nivel de equipo — sin monitoreo individual. Datos sintéticos, sin información personal (PII).

---

## 1) Contexto de negocio e impacto

### El problema
El ausentismo en organizaciones latinoamericanas tiene un costo estimado de **3 a 6% de la nómina anual** (OIT, 2023). Más allá del costo directo, los picos no detectados de ausentismo son señales de problemas subyacentes — desenganche, crisis de salud, problemas de gestión — que se agravan con el tiempo.

Los HR Business Partners habitualmente trabajan con resúmenes semanales o mensuales de dotación. Para cuando un patrón es visible en un reporte, la ventana operacional para intervenir ya se cerró.

### Qué permite este sistema
Este pipeline entrega a los HRBPs una **señal diaria de anomalías a nivel de equipo** sobre la que pueden actuar el mismo día:

- **Detección temprana:** identifica combinaciones área + turno con tasas de ausentismo estadísticamente inusuales antes de que aparezcan en reportes agregados
- **Priorización de la investigación:** las alertas ordenadas por severidad enfocan el tiempo del HRBP en el 5–10% de señales que ameritan una conversación, no en el registro completo de asistencia
- **Protección de la privacidad:** todas las alertas son a nivel de equipo — ningún individuo es identificado ni monitoreado

### Pregunta de negocio respondida diariamente
> *¿Qué combinaciones área + turno muestran un ausentismo anómalo hoy en comparación con su propio promedio de los últimos 28 días, y qué tan severa es la desviación?*

### Flujo de trabajo previsto
1. El pipeline se ejecuta durante la noche → `analytics.anomaly_alerts` se actualiza
2. El HRBP abre el dashboard de Power BI cada mañana
3. Revisa las alertas priorizadas (z-score ≥ 3, área ≥ 20 personas programadas)
4. Decide si investigar, escalar o monitorear
5. Acción operacional tomada dentro del mismo día hábil

---

## 2) Stack tecnológico
- **BigQuery**: ingesta + tablas analíticas + lógica de detección de anomalías (SQL)
- **Python (Colab)**: generación de datos sintéticos + helper de ingesta para CSV malformados
- **Power BI**: dashboard sobre `analytics.anomaly_alerts`
- **GitHub**: modelos SQL versionados, chequeos de QA y documentación

---

## 3) Datos (sintéticos, "realistas")
Este proyecto usa un dataset sintético (~3.425 empleados) diseñado para parecer realista e incluir problemas típicos de calidad de datos.

**7 archivos CSV base (capa fuente):**
- `employees_dirty.csv`
- `departments.csv`
- `performance_reviews.csv`
- `engagement.csv`
- `exits.csv`
- `shifts.csv`
- `attendance_daily.csv` *(intencionalmente desordenado / filas malformadas)*

---

## 4) Arquitectura BigQuery (Raw → Analytics)
Separamos la ingesta de los datos analíticos curados para mantener un pipeline similar a producción.

### Datasets
- `raw`: tablas de ingesta/staging
- `analytics`: tablas curadas construidas desde `raw`

### Tablas en `raw`
- `raw.attendance_daily`
- `raw.departments`
- `raw.employees_dirty`
- `raw.engagement`
- `raw.exits`
- `raw.performance_reviews`
- `raw.shifts`

### Tablas curadas en `analytics`
- `analytics.attendance_clean` (tipada + validada)
- `analytics.absence_daily` (métricas diarias por área + turno)
- `analytics.anomaly_alerts` (flags de anomalía diarios + severidad)
- `analytics.departments_clean` (nombres de área deduplicados + estandarizados)

---

## 5) Decisiones de ingeniería (qué corregimos y por qué)

### A) Fallas de ingesta CSV (asistencia)
`attendance_daily.csv` falló al cargar en BigQuery por filas CSV malformadas (BigQuery reportó ~25 errores).

**Decisión:** conservar el archivo original como evidencia y generar un archivo determinístico seguro para ingesta.
- `attendance_daily.csv` permanece como fuente original (desordenado a propósito)
- Un script helper genera:
  - `attendance_daily_ingest.csv` (cargable)
  - `ingestion_log.json` (log estructurado como evidencia)

Esto demuestra **ingesta reproducible** en lugar de correcciones manuales.

**Helper de ingesta (versionado):**
- Script: `python/sanitize_attendance.py` → genera `attendance_daily_ingest.csv` + `ingestion_log.json`
- Evidencia: `ingestion_log.json` captura filas conservadas/descartadas y sus razones.

### B) Carga de asistencia raw como STRING
Para evitar problemas de inferencia de tipos en BigQuery durante la ingesta, `raw.attendance_daily` se cargó con **todas las columnas como STRING**.

**Decisión:** aplicar tipado y validación solo aguas abajo en `analytics` (SQL), usando `SAFE_CAST`.

### C) Corrección de casting: STRING → FLOAT64 → INT64
Algunos campos numéricos llegaron como strings del tipo `"1.0"` (e.g., `department_id`, `shift_id`), lo que hace que los casteos directos retornen NULL:
- `SAFE_CAST('1.0' AS INT64)` → NULL

**Solución:** castear en dos pasos:
- `STRING → FLOAT64 → INT64`

Esta corrección está implementada en `sql/analytics/attendance_clean.sql` y evita tablas curadas vacías.

### D) Método de detección de anomalías (MVP)

Usamos una línea base simple y confiable que corre nativamente en BigQuery:

- Fuente: `analytics.absence_daily`
- Ventana móvil: **28 días previos** (excluye el día actual para evitar data leakage)
- Línea base: `mean_28d`, `std_28d`
- Score: `z_score = (absence_rate - mean_28d) / std_28d`
- Flags: `hist_days >= 14`, `scheduled_headcount >= 20`, `z_score >= 3`

#### Hallazgos clave — Ejecución MVP sobre datos sintéticos

| Métrica | Valor |
|---|---|
| Empleados en el dataset | 3.425 |
| Días analizados | ~180 |
| Combinaciones área-turno monitoreadas | ~40 |
| Total combinaciones área-turno-día flaggeadas | **103** |
| Tasa de alertas (anomalías / total área-turno-días) | ~1,4% |
| Umbral mínimo de z-score | 3,0 (≥3σ sobre línea base de 28 días) |
| Filtro mínimo de dotación | 20 empleados programados |

**Qué significa esto operacionalmente:**
- En un día promedio, **0 a 3 combinaciones área-turno** aparecerían en el dashboard del HRBP requiriendo atención
- La tasa de alertas de 1,4% es consistente con las tasas esperadas en una organización saludable
- El umbral de z-score ≥ 3 fue calibrado para minimizar falsos positivos: solo afloran las desviaciones estadísticamente significativas

**Mejora planificada:**  
La línea base actual usa media + desviación estándar (z-score). Una alternativa más robusta es mediana + MAD (Desviación Absoluta de la Mediana), menos sensible a valores atípicos históricos. El MVP prioriza un sistema funcional end-to-end sobre un modelo estadístico perfecto.

### E) Deduplicación de áreas y registros sin match

`raw.departments` contiene entradas duplicadas para el mismo departamento canónico bajo distintos IDs y variantes de nombre:

| department_id | department_name | Problema |
|---|---|---|
| 2 | Finanze | Typo — duplicado de Finance (ID 3) |
| 3 | Finance | Canónico |
| 4 | HR | Canónico |
| 9 | H.R. | Duplicado de HR (ID 4) |

**Decisión:** `analytics.departments_clean` estandariza los nombres y conserva el `department_id` más bajo para cada departamento canónico mediante `ROW_NUMBER()`.

**Consecuencia conocida:** los registros de anomalías asociados a los IDs deduplicados (2 y 9) generan filas sin match en el join de Power BI. Estos aparecen como valores en blanco en `department_name` y se filtran en la capa de visualización.

**Corrección en producción:** un paso de remapeo en SQL reasignaría los IDs huérfanos a su contraparte canónica antes del join. Documentado como mejora futura.

---

## 6) Orden de ejecución SQL (BigQuery)
Ejecutar la capa analytics en este orden exacto:

1) **attendance_clean**  
   Crea: `analytics.attendance_clean`  
   Archivo: `sql/analytics/attendance_clean.sql`

2) **absence_daily**  
   Crea: `analytics.absence_daily`  
   Archivo: `sql/analytics/absence_daily.sql`

3) **anomaly_alerts**  
   Crea: `analytics.anomaly_alerts`  
   Archivo: `sql/analytics/anomaly_alerts.sql`

4) **departments_clean**  
   Crea: `analytics.departments_clean`  
   Archivo: `sql/analytics/departments_clean.sql`

### QA (recomendado)
Después de cada paso, ejecutar:
- `sql/qa/attendance_clean_checks.sql`
- `sql/qa/absence_daily_checks.sql`
- `sql/qa/anomaly_alerts_checks.sql`

---

## 7) Estructura del repositorio
- `sql/analytics/` → modelos SQL de BigQuery (tablas curadas)
- `sql/qa/` → chequeos de QA reproducibles
- `python/` → helpers de ingesta y generación de datos sintéticos
- `data/raw/` → archivos CSV fuente (sintéticos, sin PII)
- `docs/` → esquema de datos y documentación del proyecto

---

## 8) Privacidad y ética
- Solo datos sintéticos (sin información personal real).
- Las alertas son a **nivel de equipo** (área + turno), sin monitoreo individual.
- Uso previsto: investigación operacional y prevención, no acción punitiva.

---
