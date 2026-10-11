import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="recurring-form"
// Shows "Ends after" once Repeat has a frequency and asks the server for a live summary
// 500 ms after the last change. It never formats money or computes payments.
export default class extends Controller {
  static targets = ["endsAfter", "preview", "status", "review"];
  static values = {
    previewUrl: String,
    unavailableText: String,
  };

  connect() {
    this.#applyFrequency();
    if (this.#frequency) this.schedulePreview();
  }

  disconnect() {
    clearTimeout(this.previewTimeout);
  }

  frequencyChanged() {
    this.#applyFrequency();
    this.#announce("");
    this.schedulePreview();
  }

  schedulePreview(event) {
    if (!this.hasPreviewTarget) return;
    if (event?.target && !this.#watched(event.target.name)) return;
    clearTimeout(this.previewTimeout);

    if (!this.#frequency) {
      this.#clearPreview();
      return;
    }

    this.previewTarget.setAttribute("aria-busy", "true");
    this.previewTarget.classList.add("opacity-60");
    this.previewTimeout = setTimeout(() => this.#loadPreview(), 500);
  }

  previewLoaded() {
    this.#finishLoading();

    // A response that arrives after Repeat went back to None is stale
    if (!this.#frequency) {
      this.#clearPreview();
      return;
    }

    this.#restoreProjection();

    const announcement = this.previewTarget.querySelector(
      "[data-recurring-form-announcement]",
    );
    this.#announce(announcement ? announcement.textContent.trim() : "");
  }

  previewFailed(event) {
    event.preventDefault();
    this.#finishLoading();
    this.previewTarget.removeAttribute("src");

    if (this.previewTarget.textContent.trim() === "") {
      const box = document.createElement("div");
      box.className = "rounded-lg bg-container-inset px-3 py-2";
      const message = document.createElement("p");
      message.className = "text-sm text-secondary";
      message.textContent = this.unavailableTextValue;
      box.append(message);
      this.previewTarget.replaceChildren(box);
    }

    this.#announce(this.unavailableTextValue);
  }

  // The Monthly projection disclosure is re-rendered with every summary; keep it as the person left it
  projectionToggled(event) {
    if (event.target instanceof HTMLDetailsElement) {
      this.projectionOpen = event.target.open;
    }
  }

  get #frequency() {
    const select = this.#form.elements.namedItem("recurrence[frequency]");
    return select ? select.value : "";
  }

  get #form() {
    return this.element.closest("form") || this.element;
  }

  #watched(name) {
    return (
      typeof name === "string" &&
      (name.startsWith("recurrence[") ||
        [
          "entry[account_id]",
          "entry[amount]",
          "entry[currency]",
          "entry[date]",
        ].includes(name))
    );
  }

  #applyFrequency() {
    const repeats = this.#frequency !== "";

    if (this.hasEndsAfterTarget) {
      this.endsAfterTarget.hidden = !repeats;
      this.endsAfterTarget.querySelectorAll("input").forEach((input) => {
        input.disabled = !repeats;
      });
    }

    if (this.hasReviewTarget) this.reviewTarget.disabled = !repeats;
  }

  #restoreProjection() {
    if (!this.projectionOpen) return;

    const details = this.previewTarget.querySelector(
      "[data-recurring-form-projection] details",
    );
    if (details) details.open = true;
  }

  #loadPreview() {
    const url = new URL(this.previewUrlValue, window.location.origin);
    const data = new FormData(this.#form);

    [
      "entry[account_id]",
      "entry[amount]",
      "entry[currency]",
      "entry[date]",
      "recurrence[frequency]",
      "recurrence[total_payments]",
    ].forEach((name) => {
      const value = data.get(name);
      if (value !== null) url.searchParams.set(name, value);
    });

    const src = url.toString();
    if (this.previewTarget.getAttribute("src") === src) {
      this.#finishLoading();
      return;
    }

    this.previewTarget.src = src;
  }

  #clearPreview() {
    this.previewTarget.removeAttribute("src");
    this.previewTarget.replaceChildren();
    this.#finishLoading();
  }

  #finishLoading() {
    this.previewTarget.removeAttribute("aria-busy");
    this.previewTarget.classList.remove("opacity-60");
  }

  #announce(text) {
    if (this.hasStatusTarget && this.statusTarget.textContent !== text) {
      this.statusTarget.textContent = text;
    }
  }
}
