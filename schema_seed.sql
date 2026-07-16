BEGIN;

DROP TABLE IF EXISTS funcionalidad_etiqueta CASCADE;
DROP TABLE IF EXISTS etiqueta CASCADE;
DROP TABLE IF EXISTS gasto_recurso CASCADE;
DROP TABLE IF EXISTS decision_tecnica CASCADE;
DROP TABLE IF EXISTS fragmento_codigo CASCADE;
DROP TABLE IF EXISTS nota_diseno CASCADE;
DROP TABLE IF EXISTS subtarea CASCADE;
DROP TABLE IF EXISTS funcionalidad CASCADE;
DROP TABLE IF EXISTS seccion_tablero CASCADE;
DROP TABLE IF EXISTS miembro_proyecto CASCADE;
DROP TABLE IF EXISTS proyecto CASCADE;
DROP TABLE IF EXISTS usuario CASCADE;
DROP FUNCTION IF EXISTS actualizar_fecha_funcionalidad() CASCADE;

CREATE TABLE usuario (
    id_usuario BIGSERIAL PRIMARY KEY,
    nombre_completo VARCHAR(120) NOT NULL,
    correo_electronico VARCHAR(160) NOT NULL UNIQUE,
    hash_contrasena TEXT NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'activo'
        CHECK (estado IN ('activo', 'inactivo', 'bloqueado')),
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE proyecto (
    id_proyecto BIGSERIAL PRIMARY KEY,
    id_usuario_propietario BIGINT NOT NULL
        REFERENCES usuario(id_usuario),
    nombre VARCHAR(140) NOT NULL,
    descripcion TEXT,
    proposito VARCHAR(30) NOT NULL DEFAULT 'otro'
        CHECK (proposito IN (
            'prueba_concepto',
            'portafolio',
            'aprendizaje',
            'automatizacion',
            'otro'
        )),
    estado VARCHAR(20) NOT NULL DEFAULT 'activo'
        CHECK (estado IN ('activo', 'pausado', 'completado', 'archivado')),
    fecha_inicio DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_fin_planificada DATE,
    presupuesto NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (presupuesto >= 0),
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (
        fecha_fin_planificada IS NULL
        OR fecha_fin_planificada >= fecha_inicio
    )
);

CREATE TABLE miembro_proyecto (
    id_proyecto BIGINT NOT NULL
        REFERENCES proyecto(id_proyecto) ON DELETE CASCADE,
    id_usuario BIGINT NOT NULL
        REFERENCES usuario(id_usuario) ON DELETE CASCADE,
    rol VARCHAR(30) NOT NULL DEFAULT 'colaborador'
        CHECK (rol IN ('propietario', 'colaborador', 'lector')),
    fecha_union TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_proyecto, id_usuario)
);

CREATE TABLE seccion_tablero (
    id_seccion BIGSERIAL PRIMARY KEY,
    id_proyecto BIGINT NOT NULL
        REFERENCES proyecto(id_proyecto) ON DELETE CASCADE,
    nombre VARCHAR(80) NOT NULL,
    posicion SMALLINT NOT NULL
        CHECK (posicion BETWEEN 1 AND 6),
    es_final BOOLEAN NOT NULL DEFAULT FALSE,
    limite_trabajo_en_progreso SMALLINT
        CHECK (
            limite_trabajo_en_progreso IS NULL
            OR limite_trabajo_en_progreso > 0
        ),
    UNIQUE (id_proyecto, nombre),
    UNIQUE (id_proyecto, posicion),
    UNIQUE (id_proyecto, id_seccion)
);

CREATE TABLE funcionalidad (
    id_funcionalidad BIGSERIAL PRIMARY KEY,
    id_proyecto BIGINT NOT NULL
        REFERENCES proyecto(id_proyecto) ON DELETE CASCADE,
    id_seccion BIGINT NOT NULL,
    id_usuario_creador BIGINT NOT NULL
        REFERENCES usuario(id_usuario),
    id_usuario_asignado BIGINT
        REFERENCES usuario(id_usuario),
    titulo VARCHAR(160) NOT NULL,
    historia_usuario TEXT NOT NULL,
    descripcion_detallada TEXT,
    prioridad SMALLINT NOT NULL DEFAULT 3
        CHECK (prioridad BETWEEN 1 AND 5),
    horas_estimadas NUMERIC(6,2)
        CHECK (horas_estimadas IS NULL OR horas_estimadas >= 0),
    fecha_limite DATE,
    orden INTEGER NOT NULL DEFAULT 0
        CHECK (orden >= 0),
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_proyecto, id_seccion)
        REFERENCES seccion_tablero(id_proyecto, id_seccion),
    UNIQUE (id_proyecto, id_funcionalidad)
);

CREATE TABLE subtarea (
    id_subtarea BIGSERIAL PRIMARY KEY,
    id_funcionalidad BIGINT NOT NULL
        REFERENCES funcionalidad(id_funcionalidad) ON DELETE CASCADE,
    titulo VARCHAR(180) NOT NULL,
    completada BOOLEAN NOT NULL DEFAULT FALSE,
    posicion INTEGER NOT NULL DEFAULT 0
        CHECK (posicion >= 0),
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_finalizacion TIMESTAMP,
    CHECK (
        (completada = TRUE AND fecha_finalizacion IS NOT NULL)
        OR
        (completada = FALSE AND fecha_finalizacion IS NULL)
    )
);

CREATE TABLE nota_diseno (
    id_nota BIGSERIAL PRIMARY KEY,
    id_funcionalidad BIGINT NOT NULL
        REFERENCES funcionalidad(id_funcionalidad) ON DELETE CASCADE,
    id_usuario_autor BIGINT NOT NULL
        REFERENCES usuario(id_usuario),
    titulo VARCHAR(160) NOT NULL,
    contenido TEXT NOT NULL,
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE fragmento_codigo (
    id_fragmento BIGSERIAL PRIMARY KEY,
    id_funcionalidad BIGINT NOT NULL
        REFERENCES funcionalidad(id_funcionalidad) ON DELETE CASCADE,
    id_usuario_autor BIGINT NOT NULL
        REFERENCES usuario(id_usuario),
    lenguaje VARCHAR(60) NOT NULL,
    nombre_archivo VARCHAR(180),
    codigo TEXT NOT NULL,
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE decision_tecnica (
    id_decision BIGSERIAL PRIMARY KEY,
    id_proyecto BIGINT NOT NULL
        REFERENCES proyecto(id_proyecto) ON DELETE CASCADE,
    id_funcionalidad BIGINT
        REFERENCES funcionalidad(id_funcionalidad) ON DELETE SET NULL,
    id_usuario_autor BIGINT NOT NULL
        REFERENCES usuario(id_usuario),
    titulo VARCHAR(180) NOT NULL,
    contexto TEXT NOT NULL,
    decision TEXT NOT NULL,
    consecuencias TEXT,
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE gasto_recurso (
    id_gasto BIGSERIAL PRIMARY KEY,
    id_proyecto BIGINT NOT NULL
        REFERENCES proyecto(id_proyecto) ON DELETE CASCADE,
    id_usuario_creador BIGINT NOT NULL
        REFERENCES usuario(id_usuario),
    categoria VARCHAR(40) NOT NULL
        CHECK (categoria IN (
            'nube',
            'dominio',
            'herramienta',
            'curso',
            'servicio',
            'otro'
        )),
    descripcion TEXT NOT NULL,
    monto NUMERIC(12,2) NOT NULL
        CHECK (monto >= 0),
    fecha_gasto DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE etiqueta (
    id_etiqueta BIGSERIAL PRIMARY KEY,
    nombre VARCHAR(60) NOT NULL UNIQUE
);

CREATE TABLE funcionalidad_etiqueta (
    id_funcionalidad BIGINT NOT NULL
        REFERENCES funcionalidad(id_funcionalidad) ON DELETE CASCADE,
    id_etiqueta BIGINT NOT NULL
        REFERENCES etiqueta(id_etiqueta) ON DELETE CASCADE,
    PRIMARY KEY (id_funcionalidad, id_etiqueta)
);

-- Índices para las consultas más frecuentes de la aplicación.
CREATE INDEX idx_proyecto_propietario_estado
    ON proyecto(id_usuario_propietario, estado);

CREATE INDEX idx_seccion_tablero_proyecto_posicion
    ON seccion_tablero(id_proyecto, posicion);

CREATE INDEX idx_funcionalidad_proyecto_seccion
    ON funcionalidad(id_proyecto, id_seccion);

CREATE INDEX idx_funcionalidad_asignado_prioridad
    ON funcionalidad(id_usuario_asignado, prioridad);

CREATE INDEX idx_funcionalidad_fecha_limite
    ON funcionalidad(fecha_limite);

CREATE INDEX idx_subtarea_funcionalidad_completada
    ON subtarea(id_funcionalidad, completada);

CREATE INDEX idx_gasto_recurso_proyecto_fecha
    ON gasto_recurso(id_proyecto, fecha_gasto);

-- Mantiene fecha_actualizacion sincronizada al modificar una funcionalidad.
CREATE OR REPLACE FUNCTION actualizar_fecha_funcionalidad()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.fecha_actualizacion := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_actualizar_fecha_funcionalidad
BEFORE UPDATE ON funcionalidad
FOR EACH ROW
EXECUTE FUNCTION actualizar_fecha_funcionalidad();

-- --------------------------------------------------------------------------
-- Datos simulados
-- --------------------------------------------------------------------------

INSERT INTO usuario (
    nombre_completo,
    correo_electronico,
    hash_contrasena,
    estado
) VALUES
('Pedro Gómez', 'pedro.gomez@example.com', '$2b$12$hash_simulado_pedro', 'activo'),
('Laura Martínez', 'laura.martinez@example.com', '$2b$12$hash_simulado_laura', 'activo'),
('Santiago Rojas', 'santiago.rojas@example.com', '$2b$12$hash_simulado_santiago', 'activo');

INSERT INTO proyecto (
    id_usuario_propietario,
    nombre,
    descripcion,
    proposito,
    estado,
    fecha_inicio,
    fecha_fin_planificada,
    presupuesto
) VALUES
(
    1,
    'Asistente de estudio con IA',
    'Aplicación web para organizar notas, tarjetas y sesiones de estudio.',
    'aprendizaje',
    'activo',
    '2026-07-01',
    '2026-07-28',
    2500000
),
(
    1,
    'Monitor de gastos personales',
    'Panel para registrar movimientos, categorías y metas de ahorro.',
    'automatizacion',
    'activo',
    '2026-07-05',
    '2026-08-10',
    1200000
),
(
    2,
    'API de inventario doméstico',
    'Servicio REST para controlar existencias y alertas de reposición.',
    'prueba_concepto',
    'pausado',
    '2026-06-15',
    '2026-07-21',
    800000
);

INSERT INTO miembro_proyecto (
    id_proyecto,
    id_usuario,
    rol
) VALUES
(1, 1, 'propietario'),
(1, 2, 'colaborador'),
(2, 1, 'propietario'),
(2, 3, 'lector'),
(3, 2, 'propietario');

INSERT INTO seccion_tablero (
    id_proyecto,
    nombre,
    posicion,
    es_final,
    limite_trabajo_en_progreso
) VALUES
(1, 'Pendiente',   1, FALSE, NULL),
(1, 'En progreso', 2, FALSE, 3),
(1, 'Completado',  3, TRUE,  NULL),
(1, 'Liberado',    4, TRUE,  NULL),
(2, 'Pendiente',   1, FALSE, NULL),
(2, 'En progreso', 2, FALSE, 2),
(2, 'Completado',  3, TRUE,  NULL),
(3, 'Pendiente',   1, FALSE, NULL),
(3, 'En progreso', 2, FALSE, 2),
(3, 'Completado',  3, TRUE,  NULL);

INSERT INTO funcionalidad (
    id_proyecto,
    id_seccion,
    id_usuario_creador,
    id_usuario_asignado,
    titulo,
    historia_usuario,
    descripcion_detallada,
    prioridad,
    horas_estimadas,
    fecha_limite,
    orden
) VALUES
(
    1, 1, 1, 1,
    'Recuperación de contraseña',
    'Como usuario quiero recuperar mi contraseña para volver a acceder a mi cuenta.',
    'El sistema enviará un enlace temporal al correo registrado.',
    1, 6, '2026-07-18', 1
),
(
    1, 2, 1, 2,
    'Diseñar esquema de base de datos',
    'Como desarrollador quiero definir el modelo relacional para implementar una persistencia coherente.',
    'Incluye modelo ER, transformación al modelo relacional, restricciones e índices.',
    1, 10, '2026-07-18', 1
),
(
    1, 3, 1, 1,
    'Autenticación por correo',
    'Como usuario quiero registrarme e iniciar sesión con correo y contraseña.',
    'Incluye registro, inicio de sesión, cierre de sesión y almacenamiento seguro del hash.',
    1, 9, '2026-07-12', 1
),
(
    2, 5, 1, 1,
    'Registrar movimiento financiero',
    'Como usuario quiero registrar ingresos y gastos para controlar mis finanzas.',
    'Cada movimiento incluye categoría, monto, descripción y fecha.',
    2, 8, '2026-07-24', 1
),
(
    2, 6, 1, 3,
    'Dashboard de gastos',
    'Como usuario quiero visualizar el gasto acumulado para comparar el consumo con mi presupuesto.',
    'Debe mostrar gasto total, saldo disponible y distribución por categoría.',
    1, 16, '2026-08-01', 1
),
(
    3, 8, 2, 2,
    'Registrar artículo del inventario',
    'Como usuario quiero registrar artículos para conocer las existencias disponibles.',
    'El registro incluye nombre, cantidad, ubicación y nivel mínimo de reposición.',
    3, 12, '2026-07-10', 1
);

INSERT INTO subtarea (
    id_funcionalidad,
    titulo,
    completada,
    posicion,
    fecha_finalizacion
) VALUES
(1, 'Diseñar el flujo de recuperación', TRUE, 1, '2026-07-14 09:00:00'),
(1, 'Crear el endpoint de recuperación', FALSE, 2, NULL),
(2, 'Construir el modelo ER', TRUE, 1, '2026-07-13 16:30:00'),
(2, 'Transformar el modelo ER al modelo relacional', FALSE, 2, NULL),
(2, 'Crear el script DDL inicial', FALSE, 3, NULL),
(3, 'Implementar el registro', TRUE, 1, '2026-07-10 11:00:00'),
(3, 'Implementar el inicio de sesión', TRUE, 2, '2026-07-11 15:00:00'),
(5, 'Crear tarjetas de resumen financiero', FALSE, 1, NULL),
(5, 'Crear consulta de gastos por categoría', FALSE, 2, NULL);

INSERT INTO nota_diseno (
    id_funcionalidad,
    id_usuario_autor,
    titulo,
    contenido
) VALUES
(
    1,
    1,
    'Flujo de recuperación',
    'El enlace de recuperación debe vencer y solo puede utilizarse una vez.'
),
(
    2,
    2,
    'Criterios del modelo relacional',
    'Las claves foráneas deben impedir que una funcionalidad se asocie con una sección de otro proyecto.'
),
(
    5,
    1,
    'Dashboard financiero',
    'El dashboard debe priorizar gasto acumulado, saldo y alertas del presupuesto.'
);

INSERT INTO fragmento_codigo (
    id_funcionalidad,
    id_usuario_autor,
    lenguaje,
    nombre_archivo,
    codigo
) VALUES
(
    3,
    2,
    'SQL',
    'autenticacion.sql',
    'SELECT id_usuario FROM usuario WHERE correo_electronico = $1;'
),
(
    5,
    1,
    'SQL',
    'resumen_gastos.sql',
    'SELECT categoria, SUM(monto) FROM gasto_recurso GROUP BY categoria;'
);

INSERT INTO decision_tecnica (
    id_proyecto,
    id_funcionalidad,
    id_usuario_autor,
    titulo,
    contexto,
    decision,
    consecuencias
) VALUES
(
    1,
    3,
    1,
    'Almacenar únicamente el hash de contraseña',
    'La plataforma debe proteger las credenciales de los usuarios.',
    'La aplicación nunca almacenará contraseñas en texto plano.',
    'La capa de aplicación debe utilizar una función de derivación segura, como Argon2id o bcrypt.'
),
(
    2,
    NULL,
    1,
    'Prototipo inicial con datos simulados',
    'La primera entrega debe validar el flujo antes de integrar fuentes financieras externas.',
    'El MVP utilizará datos simulados cargados desde la base de datos.',
    'La integración con servicios externos se aplaza para una iteración posterior.'
);

INSERT INTO gasto_recurso (
    id_proyecto,
    id_usuario_creador,
    categoria,
    descripcion,
    monto,
    fecha_gasto
) VALUES
(1, 1, 'dominio', 'Dominio anual del proyecto', 80000, '2026-07-02'),
(1, 1, 'nube', 'Servicio de alojamiento para pruebas', 120000, '2026-07-03'),
(2, 1, 'herramienta', 'Herramienta de diseño del prototipo', 45000, '2026-07-06'),
(2, 1, 'nube', 'Base de datos administrada para pruebas', 60000, '2026-07-08');

INSERT INTO etiqueta (nombre) VALUES
('frontend'),
('backend'),
('base-de-datos'),
('analitica'),
('seguridad');

INSERT INTO funcionalidad_etiqueta (
    id_funcionalidad,
    id_etiqueta
) VALUES
(1, 2),
(1, 5),
(2, 3),
(3, 2),
(3, 5),
(5, 3),
(5, 4);

COMMIT;

-- --------------------------------------------------------------------------
-- Consultas de verificación
-- --------------------------------------------------------------------------

SELECT 'usuario' AS tabla, COUNT(*) AS registros FROM usuario
UNION ALL
SELECT 'proyecto', COUNT(*) FROM proyecto
UNION ALL
SELECT 'miembro_proyecto', COUNT(*) FROM miembro_proyecto
UNION ALL
SELECT 'seccion_tablero', COUNT(*) FROM seccion_tablero
UNION ALL
SELECT 'funcionalidad', COUNT(*) FROM funcionalidad
UNION ALL
SELECT 'subtarea', COUNT(*) FROM subtarea
UNION ALL
SELECT 'nota_diseno', COUNT(*) FROM nota_diseno
UNION ALL
SELECT 'fragmento_codigo', COUNT(*) FROM fragmento_codigo
UNION ALL
SELECT 'decision_tecnica', COUNT(*) FROM decision_tecnica
UNION ALL
SELECT 'gasto_recurso', COUNT(*) FROM gasto_recurso
UNION ALL
SELECT 'etiqueta', COUNT(*) FROM etiqueta
UNION ALL
SELECT 'funcionalidad_etiqueta', COUNT(*) FROM funcionalidad_etiqueta
ORDER BY tabla;

SELECT
    p.id_proyecto,
    p.nombre,
    (
        SELECT COUNT(*)
        FROM seccion_tablero AS s
        WHERE s.id_proyecto = p.id_proyecto
    ) AS cantidad_secciones,
    (
        SELECT COUNT(*)
        FROM funcionalidad AS f
        WHERE f.id_proyecto = p.id_proyecto
    ) AS cantidad_funcionalidades,
    (
        SELECT COALESCE(SUM(g.monto), 0)
        FROM gasto_recurso AS g
        WHERE g.id_proyecto = p.id_proyecto
    ) AS gasto_registrado,
    p.presupuesto
FROM proyecto AS p
ORDER BY p.id_proyecto;
