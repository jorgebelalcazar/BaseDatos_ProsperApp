import os
from contextlib import asynccontextmanager
from datetime import date
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import Depends, FastAPI, HTTPException, Query, Response, status
from pydantic import BaseModel, Field
from psycopg import Connection
from psycopg.errors import ForeignKeyViolation, UniqueViolation
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool


DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://prosperapp:prosperapp123@host.docker.internal:5432/prosperapp",
)

pool = ConnectionPool(
    conninfo=DATABASE_URL,
    min_size=1,
    max_size=8,
    open=False,
    kwargs={"row_factory": dict_row},
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    pool.open(wait=True)
    yield
    pool.close()


app = FastAPI(
    title="ProsperApp API",
    version="1.0.0",
    description="API con SQL directo para el prototipo ProsperApp.",
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
    lifespan=lifespan,
)


def get_connection():
    with pool.connection() as connection:
        yield connection


DbConnection = Annotated[Connection, Depends(get_connection)]


class ProjectCreate(BaseModel):
    name: str = Field(min_length=1, max_length=140)
    description: str | None = None
    purpose: Literal[
        "prueba_concepto", "portafolio", "aprendizaje", "automatizacion", "otro"
    ] = "otro"
    deadline: date | None = None
    budget: Decimal = Field(default=Decimal("0"), ge=0)
    columns: list[str] = Field(min_length=1, max_length=6)
    owner_id: int = 1


class ChecklistItem(BaseModel):
    title: str = Field(min_length=1, max_length=180)
    completed: bool = False


class FeaturePayload(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    story: str = Field(min_length=1)
    details: str | None = None
    priority: int = Field(default=3, ge=1, le=5)
    estimated_hours: Decimal | None = Field(default=None, ge=0)
    deadline: date | None = None
    section_id: int
    assigned_user_id: int | None = None
    checklist: list[ChecklistItem] = []


class FeatureMove(BaseModel):
    section_id: int


def require_row(row, message: str = "Recurso no encontrado"):
    if row is None:
        raise HTTPException(status_code=404, detail=message)
    return row


@app.get("/api/health")
def health(connection: DbConnection):
    database_time = connection.execute("SELECT CURRENT_TIMESTAMP AS value").fetchone()
    return {"status": "ok", "database_time": database_time["value"]}


@app.get("/api/dashboard")
def dashboard(connection: DbConnection, user_id: int = Query(default=1, gt=0)):
    user = require_row(
        connection.execute(
            "SELECT id_usuario, nombre_completo, correo_electronico FROM usuario WHERE id_usuario = %s",
            (user_id,),
        ).fetchone(),
        "Usuario no encontrado",
    )

    stats = connection.execute(
        """
        SELECT
            COUNT(DISTINCT p.id_proyecto) FILTER (WHERE p.estado = 'activo') AS active_projects,
            COALESCE(SUM(p.presupuesto), 0) AS total_budget,
            COALESCE(SUM(g.total), 0) AS total_spent,
            COUNT(f.id_funcionalidad) FILTER (WHERE NOT COALESCE(s.es_final, FALSE)) AS pending_features,
            COUNT(f.id_funcionalidad) AS total_features,
            COUNT(f.id_funcionalidad) FILTER (WHERE COALESCE(s.es_final, FALSE)) AS completed_features
        FROM proyecto p
        LEFT JOIN funcionalidad f ON f.id_proyecto = p.id_proyecto
        LEFT JOIN seccion_tablero s ON s.id_seccion = f.id_seccion
        LEFT JOIN (
            SELECT id_proyecto, SUM(monto) AS total
            FROM gasto_recurso
            GROUP BY id_proyecto
        ) g ON g.id_proyecto = p.id_proyecto
        WHERE p.id_usuario_propietario = %s
        """,
        (user_id,),
    ).fetchone()

    # La unión entre proyecto y gasto repite los totales por funcionalidad; consulta las finanzas por separado.
    finances = connection.execute(
        """
        SELECT COALESCE(SUM(p.presupuesto), 0) AS total_budget,
               COALESCE(SUM(g.total), 0) AS total_spent
        FROM proyecto p
        LEFT JOIN (
            SELECT id_proyecto, SUM(monto) AS total
            FROM gasto_recurso GROUP BY id_proyecto
        ) g ON g.id_proyecto = p.id_proyecto
        WHERE p.id_usuario_propietario = %s
        """,
        (user_id,),
    ).fetchone()
    stats.update(finances)

    main_project = connection.execute(
        """
        SELECT p.id_proyecto, p.nombre, p.descripcion, p.estado, p.fecha_fin_planificada,
               p.presupuesto, COALESCE(g.total, 0) AS spent,
               COUNT(f.id_funcionalidad) AS total_features,
               COUNT(f.id_funcionalidad) FILTER (WHERE s.es_final) AS completed_features
        FROM proyecto p
        LEFT JOIN funcionalidad f ON f.id_proyecto = p.id_proyecto
        LEFT JOIN seccion_tablero s ON s.id_seccion = f.id_seccion
        LEFT JOIN (
            SELECT id_proyecto, SUM(monto) AS total FROM gasto_recurso GROUP BY id_proyecto
        ) g ON g.id_proyecto = p.id_proyecto
        WHERE p.id_usuario_propietario = %s
        GROUP BY p.id_proyecto, g.total
        ORDER BY MAX(f.fecha_actualizacion) DESC NULLS LAST, p.fecha_creacion DESC
        LIMIT 1
        """,
        (user_id,),
    ).fetchone()

    distribution = connection.execute(
        """
        SELECT s.nombre, s.es_final, COUNT(f.id_funcionalidad) AS total
        FROM seccion_tablero s
        JOIN proyecto p ON p.id_proyecto = s.id_proyecto
        LEFT JOIN funcionalidad f ON f.id_seccion = s.id_seccion
        WHERE p.id_usuario_propietario = %s
        GROUP BY s.nombre, s.es_final, s.posicion
        ORDER BY s.posicion
        """,
        (user_id,),
    ).fetchall()

    deadlines = connection.execute(
        """
        SELECT f.id_funcionalidad, f.titulo, f.fecha_limite, p.nombre AS project_name
        FROM funcionalidad f
        JOIN proyecto p ON p.id_proyecto = f.id_proyecto
        JOIN seccion_tablero s ON s.id_seccion = f.id_seccion
        WHERE p.id_usuario_propietario = %s
          AND f.fecha_limite IS NOT NULL
          AND NOT s.es_final
        ORDER BY f.fecha_limite
        LIMIT 5
        """,
        (user_id,),
    ).fetchall()

    recent_activity = connection.execute(
        """
        SELECT f.id_funcionalidad, f.titulo, f.fecha_actualizacion, p.nombre AS project_name,
               s.nombre AS section_name
        FROM funcionalidad f
        JOIN proyecto p ON p.id_proyecto = f.id_proyecto
        JOIN seccion_tablero s ON s.id_seccion = f.id_seccion
        WHERE p.id_usuario_propietario = %s
        ORDER BY f.fecha_actualizacion DESC
        LIMIT 5
        """,
        (user_id,),
    ).fetchall()

    return {
        "user": user,
        "stats": stats,
        "main_project": main_project,
        "distribution": distribution,
        "deadlines": deadlines,
        "recent_activity": recent_activity,
    }


@app.get("/api/projects")
def list_projects(
    connection: DbConnection,
    user_id: int = Query(default=1, gt=0),
    search: str = Query(default="", max_length=120),
):
    return connection.execute(
        """
        SELECT p.id_proyecto, p.nombre, p.descripcion, p.proposito, p.estado,
               p.fecha_inicio, p.fecha_fin_planificada, p.presupuesto,
               COUNT(DISTINCT f.id_funcionalidad) AS total_features,
               COUNT(DISTINCT f.id_funcionalidad) FILTER (WHERE s.es_final) AS completed_features,
               COUNT(DISTINCT m.id_usuario) AS member_count,
               COALESCE(g.total, 0) AS spent
        FROM proyecto p
        LEFT JOIN funcionalidad f ON f.id_proyecto = p.id_proyecto
        LEFT JOIN seccion_tablero s ON s.id_seccion = f.id_seccion
        LEFT JOIN miembro_proyecto m ON m.id_proyecto = p.id_proyecto
        LEFT JOIN (
            SELECT id_proyecto, SUM(monto) AS total FROM gasto_recurso GROUP BY id_proyecto
        ) g ON g.id_proyecto = p.id_proyecto
        WHERE p.id_usuario_propietario = %s
          AND (%s = '' OR p.nombre ILIKE '%%' || %s || '%%' OR COALESCE(p.descripcion, '') ILIKE '%%' || %s || '%%')
        GROUP BY p.id_proyecto, g.total
        ORDER BY p.fecha_creacion DESC
        """,
        (user_id, search, search, search),
    ).fetchall()


@app.post("/api/projects", status_code=status.HTTP_201_CREATED)
def create_project(payload: ProjectCreate, connection: DbConnection):
    clean_columns = [name.strip() for name in payload.columns if name.strip()]
    if not clean_columns or len(set(clean_columns)) != len(clean_columns):
        raise HTTPException(status_code=422, detail="Las secciones deben tener nombres únicos")

    try:
        with connection.transaction():
            project = connection.execute(
                """
                INSERT INTO proyecto (
                    id_usuario_propietario, nombre, descripcion, proposito,
                    fecha_fin_planificada, presupuesto
                ) VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING id_proyecto, nombre, descripcion, estado, fecha_fin_planificada, presupuesto
                """,
                (
                    payload.owner_id,
                    payload.name.strip(),
                    payload.description,
                    payload.purpose,
                    payload.deadline,
                    payload.budget,
                ),
            ).fetchone()
            connection.execute(
                """
                INSERT INTO miembro_proyecto (id_proyecto, id_usuario, rol)
                VALUES (%s, %s, 'propietario')
                """,
                (project["id_proyecto"], payload.owner_id),
            )
            for position, name in enumerate(clean_columns, start=1):
                connection.execute(
                    """
                    INSERT INTO seccion_tablero (id_proyecto, nombre, posicion, es_final)
                    VALUES (%s, %s, %s, %s)
                    """,
                    (
                        project["id_proyecto"],
                        name,
                        position,
                        position == len(clean_columns),
                    ),
                )
        return project
    except ForeignKeyViolation as error:
        raise HTTPException(status_code=422, detail="El usuario propietario no existe") from error
    except UniqueViolation as error:
        raise HTTPException(status_code=409, detail="Las secciones deben ser únicas") from error


@app.get("/api/projects/{project_id}/board")
def project_board(project_id: int, connection: DbConnection):
    project = require_row(
        connection.execute(
            """
            SELECT id_proyecto, nombre, descripcion, estado, fecha_fin_planificada, presupuesto
            FROM proyecto WHERE id_proyecto = %s
            """,
            (project_id,),
        ).fetchone(),
        "Proyecto no encontrado",
    )
    sections = connection.execute(
        """
        SELECT id_seccion, nombre, posicion, es_final, limite_trabajo_en_progreso
        FROM seccion_tablero WHERE id_proyecto = %s ORDER BY posicion
        """,
        (project_id,),
    ).fetchall()
    features = connection.execute(
        """
        SELECT f.id_funcionalidad, f.id_seccion, f.titulo, f.historia_usuario,
               f.descripcion_detallada, f.prioridad, f.horas_estimadas, f.fecha_limite,
               f.id_usuario_asignado, u.nombre_completo AS assigned_name,
               COALESCE(
                   json_agg(
                       json_build_object(
                           'id', st.id_subtarea,
                           'title', st.titulo,
                           'completed', st.completada
                       ) ORDER BY st.posicion
                   ) FILTER (WHERE st.id_subtarea IS NOT NULL), '[]'
               ) AS checklist
        FROM funcionalidad f
        LEFT JOIN usuario u ON u.id_usuario = f.id_usuario_asignado
        LEFT JOIN subtarea st ON st.id_funcionalidad = f.id_funcionalidad
        WHERE f.id_proyecto = %s
        GROUP BY f.id_funcionalidad, u.nombre_completo
        ORDER BY f.orden, f.fecha_creacion
        """,
        (project_id,),
    ).fetchall()
    return {"project": project, "sections": sections, "features": features}


def save_checklist(connection: Connection, feature_id: int, items: list[ChecklistItem]):
    connection.execute("DELETE FROM subtarea WHERE id_funcionalidad = %s", (feature_id,))
    for position, item in enumerate(items, start=1):
        connection.execute(
            """
            INSERT INTO subtarea (
                id_funcionalidad, titulo, completada, posicion, fecha_finalizacion
            ) VALUES (%s, %s, %s, %s, CASE WHEN %s THEN CURRENT_TIMESTAMP ELSE NULL END)
            """,
            (feature_id, item.title.strip(), item.completed, position, item.completed),
        )


@app.post("/api/projects/{project_id}/features", status_code=status.HTTP_201_CREATED)
def create_feature(project_id: int, payload: FeaturePayload, connection: DbConnection):
    creator_id = payload.assigned_user_id or 1
    try:
        with connection.transaction():
            feature = connection.execute(
                """
                INSERT INTO funcionalidad (
                    id_proyecto, id_seccion, id_usuario_creador, id_usuario_asignado,
                    titulo, historia_usuario, descripcion_detallada, prioridad,
                    horas_estimadas, fecha_limite
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING id_funcionalidad
                """,
                (
                    project_id,
                    payload.section_id,
                    creator_id,
                    payload.assigned_user_id,
                    payload.title.strip(),
                    payload.story.strip(),
                    payload.details,
                    payload.priority,
                    payload.estimated_hours,
                    payload.deadline,
                ),
            ).fetchone()
            save_checklist(connection, feature["id_funcionalidad"], payload.checklist)
        return feature
    except ForeignKeyViolation as error:
        raise HTTPException(
            status_code=422,
            detail="La sección debe pertenecer al proyecto y los usuarios deben existir",
        ) from error


@app.put("/api/features/{feature_id}")
def update_feature(feature_id: int, payload: FeaturePayload, connection: DbConnection):
    try:
        with connection.transaction():
            feature = connection.execute(
                """
                UPDATE funcionalidad
                SET id_seccion = %s, id_usuario_asignado = %s, titulo = %s,
                    historia_usuario = %s, descripcion_detallada = %s, prioridad = %s,
                    horas_estimadas = %s, fecha_limite = %s
                WHERE id_funcionalidad = %s
                RETURNING id_funcionalidad
                """,
                (
                    payload.section_id,
                    payload.assigned_user_id,
                    payload.title.strip(),
                    payload.story.strip(),
                    payload.details,
                    payload.priority,
                    payload.estimated_hours,
                    payload.deadline,
                    feature_id,
                ),
            ).fetchone()
            require_row(feature, "Funcionalidad no encontrada")
            save_checklist(connection, feature_id, payload.checklist)
        return feature
    except ForeignKeyViolation as error:
        raise HTTPException(status_code=422, detail="La sección o el usuario no son válidos") from error


@app.patch("/api/features/{feature_id}/section")
def move_feature(feature_id: int, payload: FeatureMove, connection: DbConnection):
    try:
        feature = connection.execute(
            """
            UPDATE funcionalidad SET id_seccion = %s
            WHERE id_funcionalidad = %s
            RETURNING id_funcionalidad, id_seccion
            """,
            (payload.section_id, feature_id),
        ).fetchone()
        return require_row(feature, "Funcionalidad no encontrada")
    except ForeignKeyViolation as error:
        raise HTTPException(status_code=422, detail="La sección no pertenece al proyecto") from error


@app.delete("/api/features/{feature_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_feature(feature_id: int, connection: DbConnection):
    deleted = connection.execute(
        "DELETE FROM funcionalidad WHERE id_funcionalidad = %s RETURNING id_funcionalidad",
        (feature_id,),
    ).fetchone()
    require_row(deleted, "Funcionalidad no encontrada")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/api/work")
def assigned_work(connection: DbConnection, user_id: int = Query(default=1, gt=0)):
    return connection.execute(
        """
        SELECT f.id_funcionalidad, f.titulo, f.prioridad, f.fecha_limite,
               f.horas_estimadas, p.nombre AS project_name, s.nombre AS section_name,
               COUNT(st.id_subtarea) AS checklist_total,
               COUNT(st.id_subtarea) FILTER (WHERE st.completada) AS checklist_completed
        FROM funcionalidad f
        JOIN proyecto p ON p.id_proyecto = f.id_proyecto
        JOIN seccion_tablero s ON s.id_seccion = f.id_seccion
        LEFT JOIN subtarea st ON st.id_funcionalidad = f.id_funcionalidad
        WHERE f.id_usuario_asignado = %s AND NOT s.es_final
        GROUP BY f.id_funcionalidad, p.nombre, s.nombre
        ORDER BY f.prioridad, f.fecha_limite NULLS LAST
        """,
        (user_id,),
    ).fetchall()


@app.get("/api/reports/budget")
def budget_report(connection: DbConnection, user_id: int = Query(default=1, gt=0)):
    return connection.execute(
        """
        SELECT p.id_proyecto, p.nombre, p.presupuesto,
               COALESCE(SUM(g.monto), 0) AS spent
        FROM proyecto p
        LEFT JOIN gasto_recurso g ON g.id_proyecto = p.id_proyecto
        WHERE p.id_usuario_propietario = %s
        GROUP BY p.id_proyecto
        ORDER BY p.fecha_creacion
        """,
        (user_id,),
    ).fetchall()


@app.get("/api/reports/completions")
def completion_report(connection: DbConnection, user_id: int = Query(default=1, gt=0)):
    return connection.execute(
        """
        WITH weeks AS (
            SELECT generate_series(
                date_trunc('week', CURRENT_DATE) - INTERVAL '5 weeks',
                date_trunc('week', CURRENT_DATE),
                INTERVAL '1 week'
            ) AS week_start
        ), owned_features AS (
            SELECT f.id_funcionalidad, f.id_seccion, f.fecha_actualizacion
            FROM funcionalidad f
            JOIN proyecto p ON p.id_proyecto = f.id_proyecto
            WHERE p.id_usuario_propietario = %s
        )
        SELECT w.week_start::date,
               COUNT(f.id_funcionalidad) FILTER (WHERE s.es_final) AS completed
        FROM weeks w
        LEFT JOIN owned_features f
          ON f.fecha_actualizacion >= w.week_start
         AND f.fecha_actualizacion < w.week_start + INTERVAL '1 week'
        LEFT JOIN seccion_tablero s ON s.id_seccion = f.id_seccion
        GROUP BY w.week_start
        ORDER BY w.week_start
        """,
        (user_id,),
    ).fetchall()
