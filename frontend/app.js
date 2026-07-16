const defaults = ["Pendiente", "En progreso", "Completado", "Liberado"];
const state = { projects: [], activeProject: null, board: null, dashboard: null };
let editingFeatureId = null;
let searchTerm = "";

const qs = (selector) => document.querySelector(selector);
const qsa = (selector) => [...document.querySelectorAll(selector)];
const money = new Intl.NumberFormat("es-CO", { style: "currency", currency: "COP", maximumFractionDigits: 0 });
const shortDate = new Intl.DateTimeFormat("es-CO", { day: "numeric", month: "short", year: "numeric" });
const compactDate = new Intl.DateTimeFormat("es-CO", { day: "numeric", month: "short" });

function escapeHtml(value = "") {
  return String(value).replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;",
  })[character]);
}

function initials(value = "") {
  return value.split(/\s+/).slice(0, 2).map((word) => word[0]).join("").toUpperCase();
}

function priorityName(value) {
  if (Number(value) <= 2) return "alta";
  if (Number(value) === 3) return "media";
  return "baja";
}

function priorityValue(value) {
  return { alta: 1, media: 3, baja: 5 }[value] || 3;
}

function percent(completed, total) {
  return total ? Math.round((Number(completed) / Number(total)) * 100) : 0;
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
  });
  if (!response.ok) {
    let message = `Error ${response.status}`;
    try {
      const body = await response.json();
      message = typeof body.detail === "string" ? body.detail : message;
    } catch (_) {
      // Conserva el estado HTTP cuando la respuesta no contiene JSON.
    }
    throw new Error(message);
  }
  return response.status === 204 ? null : response.json();
}

function toast(message) {
  const element = qs("#toast");
  element.textContent = message;
  element.classList.add("show");
  clearTimeout(window.__toast);
  window.__toast = setTimeout(() => element.classList.remove("show"), 2200);
}

function handleError(error) {
  console.error(error);
  toast(error.message || "No se pudo completar la operación");
}

async function showView(name) {
  qsa(".view").forEach((view) => view.classList.remove("active"));
  qs(`#view-${name}`)?.classList.add("active");
  qsa(".nav button").forEach((button) => button.classList.toggle("active", button.dataset.view === name));
  qs("#sidebar").classList.remove("open");
  try {
    if (name === "proyectos") await loadProjects();
    if (name === "tablero" && state.activeProject) await loadBoard(state.activeProject);
    if (name === "trabajo") await loadWork();
    if (name === "reportes") await loadBudgetReport();
  } catch (error) {
    handleError(error);
  }
}

async function loadDashboard() {
  const data = await api("/api/dashboard?user_id=1");
  state.dashboard = data;
  const { user, stats, main_project: project } = data;
  const firstName = user.nombre_completo.split(" ")[0];
  const total = Number(stats.total_features);
  const completed = Number(stats.completed_features);
  const progress = percent(completed, total);
  const available = Number(stats.total_budget) - Number(stats.total_spent);

  qs("#welcomeTitle").textContent = `Buenos días, ${firstName}`;
  qs(".profile strong").textContent = user.nombre_completo;
  qs(".profile .avatar").textContent = initials(user.nombre_completo);
  qs("#statProjects").textContent = stats.active_projects;
  qs("#statPending").textContent = stats.pending_features;
  qs("#statProgress").textContent = `${progress}%`;
  qs("#statBudget").textContent = money.format(Math.max(0, available));
  qs("#statBudgetDetail").textContent = `${money.format(stats.total_spent)} ejecutados`;
  qs("#usageCount").textContent = `${stats.active_projects}/6`;
  qs("#usageBar").style.width = `${Math.min(100, (Number(stats.active_projects) / 6) * 100)}%`;

  if (project) {
    const projectProgress = percent(project.completed_features, project.total_features);
    state.activeProject = Number(localStorage.getItem("prosperapp-project")) || project.id_proyecto;
    qs("#mainProject").innerHTML = `
      <div class="project-top">
        <div class="project-title"><div class="project-logo">${escapeHtml(initials(project.nombre))}</div>
          <div><h3>${escapeHtml(project.nombre)}</h3><p>${escapeHtml(project.descripcion || "Sin descripción")}</p></div>
        </div>
        <span class="badge success">${escapeHtml(project.estado)}</span>
      </div>
      <div class="project-metrics">
        <div class="mini-metric"><span>Progreso</span><strong>${projectProgress}%</strong></div>
        <div class="mini-metric"><span>Funcionalidades</span><strong>${project.completed_features}/${project.total_features}</strong></div>
        <div class="mini-metric"><span>Entrega estimada</span><strong>${project.fecha_fin_planificada ? shortDate.format(new Date(`${project.fecha_fin_planificada}T00:00:00`)) : "Sin fecha"}</strong></div>
      </div>
      <div class="progress"><span style="width:${projectProgress}%"></span></div>`;
  }

  qs("#activityList").innerHTML = data.recent_activity.length ? data.recent_activity.map((item) => `
    <div class="activity"><div class="dot">↔</div>
      <div><p><strong>${escapeHtml(item.titulo)}</strong> está en ${escapeHtml(item.section_name)}</p><small>${escapeHtml(item.project_name)}</small></div>
      <small>${compactDate.format(new Date(item.fecha_actualizacion))}</small>
    </div>`).join("") : '<div class="empty">No hay actividad reciente.</div>';

  const distributionTotal = data.distribution.reduce((sum, item) => sum + Number(item.total), 0);
  const distributionDone = data.distribution.filter((item) => item.es_final).reduce((sum, item) => sum + Number(item.total), 0);
  const donePercent = percent(distributionDone, distributionTotal);
  qs("#workDonut").style.background = `conic-gradient(var(--primary) 0 ${donePercent}%, var(--line) ${donePercent}%)`;
  qs("#workDonut").style.setProperty("--donut-label", `"${donePercent}%"`);
  qs("#workLegend").innerHTML = data.distribution.map((item) => `
    <div class="legend-row"><span>${escapeHtml(item.nombre)}</span><strong>${item.total}</strong></div>`).join("");

  qs("#deadlineList").innerHTML = data.deadlines.length ? data.deadlines.map((item) => {
    const deadline = new Date(`${item.fecha_limite}T00:00:00`);
    return `<div class="deadline"><div class="date-box"><b>${deadline.getDate()}</b><small>${deadline.toLocaleDateString("es-CO", { month: "short" })}</small></div>
      <div><strong>${escapeHtml(item.titulo)}</strong><p>${escapeHtml(item.project_name)}</p></div>
      <span class="badge neutral">${compactDate.format(deadline)}</span></div>`;
  }).join("") : '<div class="empty">No hay fechas próximas.</div>';
}

async function loadProjects() {
  state.projects = await api(`/api/projects?user_id=1&search=${encodeURIComponent(searchTerm)}`);
  renderProjects();
}

function renderProjects() {
  const grid = qs("#projectsGrid");
  grid.innerHTML = state.projects.map((project, index) => {
    const progress = percent(project.completed_features, project.total_features);
    return `<article class="project-card">
      <div class="project-card-top">
        <div class="project-logo" style="background:${index % 2 ? "linear-gradient(135deg,#0ea5e9,#22c55e)" : "linear-gradient(135deg,#5b5ce2,#8b5cf6)"}">${escapeHtml(initials(project.nombre))}</div>
        <span class="badge ${project.estado === "activo" ? "success" : "warning"}">${escapeHtml(project.estado)}</span>
      </div>
      <h3>${escapeHtml(project.nombre)}</h3><p>${escapeHtml(project.descripcion || "Sin descripción")}</p>
      <div class="progress"><span style="width:${progress}%"></span></div>
      <div style="display:flex;justify-content:space-between;color:var(--muted);font-size:11px"><span>${progress}% completado</span><span>${project.fecha_fin_planificada ? shortDate.format(new Date(`${project.fecha_fin_planificada}T00:00:00`)) : "Sin fecha"}</span></div>
      <div class="project-card-footer"><div class="avatars"><span>${project.member_count}</span></div>
        <button class="secondary-btn open-project" data-id="${project.id_proyecto}">Abrir tablero</button></div>
    </article>`;
  }).join("") || '<div class="empty">No se encontraron proyectos.</div>';
  qsa(".open-project").forEach((button) => button.addEventListener("click", () => openProject(button.dataset.id)));
}

async function openProject(id) {
  state.activeProject = Number(id);
  localStorage.setItem("prosperapp-project", state.activeProject);
  await loadBoard(state.activeProject);
  await showView("tablero");
}

async function loadBoard(projectId) {
  state.board = await api(`/api/projects/${projectId}/board`);
  qs("#boardProjectTitle").textContent = state.board.project.nombre;
  qs("#boardProjectDesc").textContent = state.board.project.descripcion || "Sin descripción";
  const finalSections = new Set(state.board.sections.filter((section) => section.es_final).map((section) => section.id_seccion));
  const completed = state.board.features.filter((feature) => finalSections.has(feature.id_seccion)).length;
  qs("#boardProgress").textContent = `${percent(completed, state.board.features.length)}% completado`;
  qs("#boardDeadline").textContent = state.board.project.fecha_fin_planificada
    ? `Entrega ${compactDate.format(new Date(`${state.board.project.fecha_fin_planificada}T00:00:00`))}`
    : "Sin fecha";
  renderBoard();
}

function renderBoard() {
  if (!state.board) return;
  const selectedPriority = qs("#priorityFilter").value;
  const board = qs("#board");
  board.innerHTML = state.board.sections.map((section) => {
    const features = state.board.features
      .filter((feature) => feature.id_seccion === section.id_seccion)
      .filter((feature) => !selectedPriority || priorityName(feature.prioridad) === selectedPriority)
      .filter((feature) => `${feature.titulo} ${feature.historia_usuario}`.toLowerCase().includes(searchTerm));
    return `<section class="column" data-column="${section.id_seccion}">
      <div class="column-head"><div class="column-title"><span>${escapeHtml(section.nombre)}</span><span class="count">${features.length}</span></div>
        <button class="icon-btn add-in-column" data-column="${section.id_seccion}" style="width:30px;height:30px;border-radius:9px">＋</button></div>
      <div class="cards">${features.map(taskCard).join("")}</div>
      <button class="add-card add-in-column" data-column="${section.id_seccion}">＋ Añadir funcionalidad</button>
    </section>`;
  }).join("");

  qsa(".task").forEach((element) => {
    element.addEventListener("dragstart", (event) => event.dataTransfer.setData("text/plain", element.dataset.id));
    element.addEventListener("click", () => openFeature(Number(element.dataset.id)));
  });
  qsa(".column").forEach((column) => {
    column.addEventListener("dragover", (event) => { event.preventDefault(); column.classList.add("drag-over"); });
    column.addEventListener("dragleave", () => column.classList.remove("drag-over"));
    column.addEventListener("drop", async (event) => {
      event.preventDefault();
      column.classList.remove("drag-over");
      try {
        await api(`/api/features/${event.dataTransfer.getData("text/plain")}/section`, {
          method: "PATCH", body: JSON.stringify({ section_id: Number(column.dataset.column) }),
        });
        await refreshApplicationData();
        toast("Estado actualizado");
      } catch (error) { handleError(error); }
    });
  });
  qsa(".add-in-column").forEach((button) => button.addEventListener("click", (event) => {
    event.stopPropagation();
    openFeature(null, Number(button.dataset.column));
  }));
  populateStatusSelect();
}

function taskCard(feature) {
  const done = feature.checklist.filter((item) => item.completed).length;
  const priority = priorityName(feature.prioridad);
  return `<article class="task" draggable="true" data-id="${feature.id_funcionalidad}">
    <div class="task-tags"><span class="priority ${priority}">${priority.toUpperCase()}</span><span class="badge neutral">${feature.horas_estimadas ? `${feature.horas_estimadas} h` : "Sin estimar"}</span></div>
    <h4>${escapeHtml(feature.titulo)}</h4><p>${escapeHtml(feature.historia_usuario)}</p>
    <div class="task-footer"><div class="task-meta"><span>▣ ${done}/${feature.checklist.length}</span><span>◷ ${feature.fecha_limite ? compactDate.format(new Date(`${feature.fecha_limite}T00:00:00`)) : "Sin fecha"}</span></div>
      <span class="avatar" style="width:24px;height:24px;font-size:9px">${escapeHtml(initials(feature.assigned_name || "Sin asignar"))}</span></div>
  </article>`;
}

async function loadWork() {
  const work = await api("/api/work?user_id=1");
  qs("#workTable").innerHTML = work.map((feature) => {
    const progress = percent(feature.checklist_completed, feature.checklist_total);
    const priority = priorityName(feature.prioridad);
    return `<tr><td><strong>${escapeHtml(feature.titulo)}</strong></td><td>${escapeHtml(feature.project_name)}</td>
      <td><span class="badge neutral">${escapeHtml(feature.section_name)}</span></td><td><span class="priority ${priority}">${priority}</span></td>
      <td>${feature.fecha_limite ? compactDate.format(new Date(`${feature.fecha_limite}T00:00:00`)) : "—"}</td>
      <td><div class="progress" style="width:110px"><span style="width:${progress}%"></span></div></td></tr>`;
  }).join("") || '<tr><td colspan="6" class="empty">No hay trabajo pendiente.</td></tr>';
}

async function loadBudgetReport() {
  const [projects, completions] = await Promise.all([
    api("/api/reports/budget?user_id=1"),
    api("/api/reports/completions?user_id=1"),
  ]);
  qs("#budgetReport").innerHTML = projects.map((project) => {
    const execution = Number(project.presupuesto) ? Math.min(100, Math.round((Number(project.spent) / Number(project.presupuesto)) * 100)) : 0;
    return `<div><div class="legend-row"><span>${escapeHtml(project.nombre)}</span><strong>${execution}%</strong></div>
      <div class="progress" style="margin-top:7px"><span style="width:${execution}%"></span></div>
      <small style="color:var(--muted)">${money.format(project.spent)} de ${money.format(project.presupuesto)}</small></div>`;
  }).join("") || '<div class="empty">No hay presupuestos.</div>';
  const maximum = Math.max(1, ...completions.map((item) => Number(item.completed)));
  qs("#completionReport").innerHTML = completions.map((item) => {
    const height = Math.max(4, Math.round((Number(item.completed) / maximum) * 100));
    const label = compactDate.format(new Date(`${item.week_start}T00:00:00`));
    return `<div class="bar-wrap"><strong>${item.completed}</strong><div class="bar" style="height:${height}%"></div><span>${label}</span></div>`;
  }).join("");
}

const projectDialog = qs("#projectDialog");
function renderColumnInputs() {
  const count = Number(qs("#columnCount").value);
  qs("#columnsPreview").innerHTML = Array.from({ length: count }, (_, index) => `
    <div class="column-name"><span class="count">${index + 1}</span><input class="new-column-name" value="${defaults[index] || `Sección ${index + 1}`}" required /></div>`).join("");
}

async function createProject(event) {
  if (event.submitter?.value === "cancel") return;
  event.preventDefault();
  const payload = {
    name: qs("#projectName").value.trim(),
    description: qs("#projectDescription").value.trim() || null,
    deadline: qs("#projectDeadline").value || null,
    budget: Number(qs("#projectBudget").value) || 0,
    columns: qsa(".new-column-name").map((input) => input.value.trim()),
    owner_id: 1,
  };
  try {
    const project = await api("/api/projects", { method: "POST", body: JSON.stringify(payload) });
    projectDialog.close();
    qs("#projectForm").reset();
    qs("#columnCount").value = 4;
    renderColumnInputs();
    await loadDashboard();
    await openProject(project.id_proyecto);
    toast("Proyecto creado");
  } catch (error) { handleError(error); }
}

const featureDialog = qs("#featureDialog");
function populateStatusSelect() {
  qs("#featureStatus").innerHTML = (state.board?.sections || []).map((section) => `
    <option value="${section.id_seccion}">${escapeHtml(section.nombre)}</option>`).join("");
}

function openFeature(id = null, sectionId = null) {
  editingFeatureId = id;
  populateStatusSelect();
  const feature = state.board?.features.find((item) => item.id_funcionalidad === id);
  qs("#featureModalTitle").textContent = feature ? "Editar funcionalidad" : "Nueva funcionalidad";
  qs("#deleteFeature").style.display = feature ? "inline-flex" : "none";
  qs("#featureTitle").value = feature?.titulo || "";
  qs("#featureDescription").value = feature?.historia_usuario || "";
  qs("#featurePriority").value = feature ? priorityName(feature.prioridad) : "media";
  qs("#featureStatus").value = feature?.id_seccion || sectionId || state.board?.sections[0]?.id_seccion;
  qs("#featureDate").value = feature?.fecha_limite || "";
  qs("#featureEstimate").value = feature?.horas_estimadas || "";
  qs("#checklist").innerHTML = (feature?.checklist || []).map((item) => checkTemplate(item.title, item.completed)).join("");
  bindChecklistRemove();
  featureDialog.showModal();
}

function checkTemplate(text = "", done = false) {
  return `<div class="check-item"><input type="checkbox" ${done ? "checked" : ""}/>
    <input class="check-text" value="${escapeHtml(text)}" placeholder="Descripción de la subtarea" style="flex:1"/>
    <button type="button" class="icon-btn remove-check" style="width:30px;height:30px">×</button></div>`;
}

function bindChecklistRemove() {
  qsa(".remove-check").forEach((button) => { button.onclick = () => button.closest(".check-item").remove(); });
}

async function saveFeature(event) {
  if (event.submitter?.value === "cancel") return;
  event.preventDefault();
  const estimate = qs("#featureEstimate").value.trim().replace(",", ".").match(/\d+(?:\.\d+)?/);
  const payload = {
    title: qs("#featureTitle").value.trim(),
    story: qs("#featureDescription").value.trim() || "Sin descripción",
    priority: priorityValue(qs("#featurePriority").value),
    section_id: Number(qs("#featureStatus").value),
    deadline: qs("#featureDate").value || null,
    estimated_hours: estimate ? Number(estimate[0]) : null,
    assigned_user_id: 1,
    checklist: qsa("#checklist .check-item").map((row) => ({
      title: row.querySelector(".check-text").value.trim(),
      completed: row.querySelector('input[type="checkbox"]').checked,
    })).filter((item) => item.title),
  };
  try {
    const path = editingFeatureId ? `/api/features/${editingFeatureId}` : `/api/projects/${state.activeProject}/features`;
    await api(path, { method: editingFeatureId ? "PUT" : "POST", body: JSON.stringify(payload) });
    featureDialog.close();
    await refreshApplicationData();
    toast(editingFeatureId ? "Funcionalidad actualizada" : "Funcionalidad creada");
  } catch (error) { handleError(error); }
}

async function deleteFeature() {
  if (!editingFeatureId) return;
  try {
    await api(`/api/features/${editingFeatureId}`, { method: "DELETE" });
    featureDialog.close();
    await refreshApplicationData();
    toast("Funcionalidad eliminada");
  } catch (error) { handleError(error); }
}

async function refreshApplicationData() {
  await Promise.all([loadBoard(state.activeProject), loadDashboard()]);
}

function bindEvents() {
  qsa(".nav button").forEach((button) => button.addEventListener("click", () => showView(button.dataset.view)));
  qs("#mobileMenu").addEventListener("click", () => qs("#sidebar").classList.toggle("open"));
  [qs("#newProjectBtn"), qs("#newProjectBtn2")].forEach((button) => button.addEventListener("click", () => {
    renderColumnInputs(); projectDialog.showModal();
  }));
  qs("#columnCount").addEventListener("input", renderColumnInputs);
  qs("#projectForm").addEventListener("submit", createProject);
  qs("#addFeatureBtn").addEventListener("click", () => openFeature());
  qs("#addChecklist").addEventListener("click", () => { qs("#checklist").insertAdjacentHTML("beforeend", checkTemplate()); bindChecklistRemove(); });
  qs("#featureForm").addEventListener("submit", saveFeature);
  qs("#deleteFeature").addEventListener("click", deleteFeature);
  qs("#priorityFilter").addEventListener("change", renderBoard);
  qs("#clearFilters").addEventListener("click", () => { qs("#priorityFilter").value = ""; qs("#globalSearch").value = ""; searchTerm = ""; renderBoard(); });
  qs("#globalSearch").addEventListener("input", async (event) => {
    searchTerm = event.target.value.toLowerCase().trim();
    const active = qs(".view.active").id.replace("view-", "");
    if (active === "proyectos") await loadProjects();
    if (active === "tablero") renderBoard();
  });
  qs("#openMainBoard").addEventListener("click", () => {
    const mainId = state.dashboard?.main_project?.id_proyecto;
    if (mainId) openProject(mainId).catch(handleError);
  });
  qs("#themeToggle").addEventListener("click", () => {
    const dark = document.documentElement.dataset.theme === "dark";
    document.documentElement.dataset.theme = dark ? "light" : "dark";
    localStorage.setItem("prosperapp-theme", dark ? "light" : "dark");
  });
  qsa(".switch").forEach((element) => element.addEventListener("click", () => element.classList.toggle("on")));
}

async function initialize() {
  document.documentElement.dataset.theme = localStorage.getItem("prosperapp-theme") || "light";
  bindEvents();
  renderColumnInputs();
  try {
    await Promise.all([loadDashboard(), loadProjects(), loadWork(), loadBudgetReport()]);
    if (state.activeProject) await loadBoard(state.activeProject);
    qs("#connectionStatus").textContent = "Datos sincronizados con PostgreSQL";
  } catch (error) {
    qs("#connectionStatus").textContent = "Sin conexión con la API";
    handleError(error);
  }
}

initialize();
