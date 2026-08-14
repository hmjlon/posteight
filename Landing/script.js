const reveals = document.querySelectorAll(".reveal");

const revealObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-visible");
      revealObserver.unobserve(entry.target);
    });
  },
  { threshold: 0.14 }
);

reveals.forEach((element) => revealObserver.observe(element));

document.querySelectorAll(".todo input").forEach((input) => {
  input.addEventListener("change", () => {
    input.closest(".todo").classList.toggle("is-done", input.checked);
  });
});

const customNote = document.querySelector("#customNote");
document.querySelectorAll(".swatch").forEach((swatch) => {
  swatch.addEventListener("click", () => {
    document.querySelector(".swatch.active")?.classList.remove("active");
    swatch.classList.add("active");
    customNote.style.setProperty("--note-color", swatch.dataset.color);
  });
});

const tiltTarget = document.querySelector("[data-tilt]");
const heroStage = document.querySelector(".hero-stage");
const hasFinePointer = window.matchMedia("(pointer: fine)").matches;

if (hasFinePointer && tiltTarget && heroStage) {
  heroStage.addEventListener("pointermove", (event) => {
    const rect = heroStage.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width - 0.5;
    const y = (event.clientY - rect.top) / rect.height - 0.5;
    tiltTarget.style.transform = `rotateY(${x * 7 - 5}deg) rotateX(${-y * 6 + 2}deg) rotateZ(1deg) translate3d(${x * 8}px, ${y * 8}px, 0)`;
  });

  heroStage.addEventListener("pointerleave", () => {
    tiltTarget.style.transform = "rotateY(-5deg) rotateX(2deg) rotateZ(1deg)";
  });
}

const addTodoButton = document.querySelector(".add-todo");
addTodoButton?.addEventListener("click", () => {
  const checklist = addTodoButton.previousElementSibling;
  const row = document.createElement("label");
  row.className = "todo";
  row.innerHTML = `
    <input type="checkbox" />
    <span class="checkmark"></span>
    <span class="todo-copy">새로운 할 일</span>
  `;
  const input = row.querySelector("input");
  input.addEventListener("change", () => row.classList.toggle("is-done", input.checked));
  checklist.appendChild(row);
});

const downloadButton = document.querySelector("#downloadButton");
const toast = document.querySelector("#toast");
let toastTimer;

downloadButton?.addEventListener("click", () => {
  window.clearTimeout(toastTimer);
  toast.classList.add("show");
  toastTimer = window.setTimeout(() => toast.classList.remove("show"), 4200);
});

toast?.querySelector("button").addEventListener("click", () => toast.classList.remove("show"));
