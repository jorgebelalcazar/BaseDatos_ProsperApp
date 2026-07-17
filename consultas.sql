-- Consulta 1 - proyectos por propietario
SELECT
    u.nombre_completo,
    u.correo_electronico,
    p.nombre AS proyecto,
    p.estado,
    p.fecha_fin_planificada,
    p.presupuesto
FROM usuario AS u
JOIN proyecto AS p
    ON p.id_usuario_propietario = u.id_usuario
ORDER BY
    u.nombre_completo,
    p.nombre;

-- Consulta 2 - tablero de un proyecto

SELECT
    p.nombre AS proyecto,
    s.nombre AS seccion,
    s.posicion,
    f.titulo AS funcionalidad,
    f.prioridad,
    f.fecha_limite
FROM proyecto AS p
JOIN seccion_tablero AS s
    ON s.id_proyecto = p.id_proyecto
LEFT JOIN funcionalidad AS f
    ON f.id_seccion = s.id_seccion
WHERE p.nombre = 'Asistente de estudio con IA'
ORDER BY
    s.posicion,
    f.prioridad,
    f.fecha_limite;

-- Consulta 3 - progreso de los proyectos

SELECT
    p.nombre AS proyecto,
    COUNT(f.id_funcionalidad) AS total_funcionalidades,
    COUNT(f.id_funcionalidad)
        FILTER (
            WHERE LOWER(s.nombre) IN ('completado', 'completed', 'release')
        ) AS funcionalidades_finalizadas,
    ROUND(
        100.0 *
        COUNT(f.id_funcionalidad)
            FILTER (
                WHERE LOWER(s.nombre) IN ('completado', 'completed', 'release')
            )
        / NULLIF(COUNT(f.id_funcionalidad), 0),
        2
    ) AS porcentaje_avance
FROM proyecto AS p
LEFT JOIN funcionalidad AS f
    ON f.id_proyecto = p.id_proyecto
LEFT JOIN seccion_tablero AS s
    ON s.id_seccion = f.id_seccion
GROUP BY p.id_proyecto, p.nombre
ORDER BY porcentaje_avance DESC NULLS LAST;

-- Consulta 4 - subtareas pendientes

SELECT
    p.nombre AS proyecto,
    f.titulo AS funcionalidad,
    st.titulo AS subtarea,
    st.posicion
FROM subtarea AS st
JOIN funcionalidad AS f
    ON f.id_funcionalidad = st.id_funcionalidad
JOIN proyecto AS p
    ON p.id_proyecto = f.id_proyecto
WHERE st.completada = FALSE
ORDER BY
    p.nombre,
    f.titulo,
    st.posicion;
