for (const exercise of document.querySelectorAll("[data-exercise]")) {
  exercise.hidden = false;
  exercise.addEventListener("click", (event) => {
    const answer = event.target.closest("button[data-feedback]");
    if (answer) exercise.querySelector("output").textContent = answer.dataset.feedback;
  });
}
const calculator = document.querySelector("[data-calculator]");
if (calculator) {
  calculator.hidden = false;
  const update = () => {
    const selected = [...calculator.querySelectorAll("input:checked")];
    const points = selected.reduce((sum, card) => sum + Number(card.value), 0);
    calculator.querySelector("output").textContent = `${selected.length} selected · ${points} card points`;
  };
  calculator.addEventListener("change", update);
  update();
}
