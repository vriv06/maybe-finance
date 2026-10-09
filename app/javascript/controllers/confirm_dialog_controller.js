import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="confirm-dialog"
// See javascript/controllers/application.js for how this is wired up
export default class extends Controller {
  static targets = ["title", "subtitle", "confirmButton", "cancelButton"];

  handleConfirm(rawData) {
    const data = this.#normalizeRawData(rawData);

    this.#prepareDialog(data);

    this.element.returnValue = "";
    this.element.showModal();

    // With a secondary button, the safe choice gets the initial focus (destructive confirms)
    if (data.cancelText) this.cancelButtonTarget.focus();

    return new Promise((resolve) => {
      this.element.addEventListener(
        "close",
        () => {
          const isConfirmed = this.element.returnValue === "confirm";
          resolve(isConfirmed);
        },
        { once: true },
      );
    });
  }

  #prepareDialog(data) {
    const variant = data.variant || "primary";

    this.confirmButtonTargets.forEach((button) => {
      if (button.dataset.variant === variant) {
        button.removeAttribute("hidden");
      } else {
        button.setAttribute("hidden", true);
      }

      button.textContent = data.confirmText || "Confirm";
    });

    if (data.cancelText) {
      this.cancelButtonTarget.textContent = data.cancelText;
      this.cancelButtonTarget.removeAttribute("hidden");
    } else {
      this.cancelButtonTarget.setAttribute("hidden", true);
    }

    this.titleTarget.textContent = data.title || "Are you sure?";
    this.subtitleTarget.innerHTML =
      data.body || "This action cannot be undone.";
  }

  // If data is a string, it's the title.  Otherwise, return the parsed object.
  #normalizeRawData(rawData) {
    try {
      const parsed = JSON.parse(rawData);

      if (typeof parsed === "boolean") {
        return { title: "Are you sure?" };
      }

      return parsed;
    } catch (e) {
      return { title: rawData };
    }
  }
}
