import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="recurring-form"
// Shows the fields of the chosen recurring payment type and asks the server for a
// live summary 500 ms after the last change. It never formats money or computes payments.
export default class extends Controller {
  static targets = ["fields", "installmentsOption", "firstPayment", "preview", "status", "review"];
  static values = {
    previewUrl: String,
    creditAccountIds: Array,
    accountId: String,
    unavailableText: String,
    creditOnlyText: String,
  };

  connect() {
    this.#syncInstallmentsOption();
    this.#applyType();
    if (this.#planType) this.schedulePreview();
  }

  disconnect() {
    clearTimeout(this.previewTimeout);
  }

  selectType() {
    this.#applyType();
    this.#toggleCreditOnlyNote(false);
    this.#announce("");
    this.schedulePreview();
  }

  accountChanged() {
    this.#syncInstallmentsOption();
    this.schedulePreview();
  }

  syncFirstPayment(event) {
    if (!this.hasFirstPaymentTarget || this.firstPaymentTarget.dataset.edited === "true") return;

    const nextMonth = this.#addOneMonth(event.target.value);
    if (nextMonth) this.firstPaymentTarget.value = nextMonth;
  }

  markFirstPaymentEdited() {
    this.firstPaymentTarget.dataset.edited = "true";
  }

  schedulePreview(event) {
    if (!this.hasPreviewTarget) return;
    if (event && event.target && !this.#watched(event.target.name)) return;
    clearTimeout(this.previewTimeout);

    if (!this.#planType) {
      this.#clearPreview();
      return;
    }

    this.previewTarget.setAttribute("aria-busy", "true");
    this.previewTarget.classList.add("opacity-60");
    this.previewTimeout = setTimeout(() => this.#loadPreview(), 500);
  }

  previewLoaded() {
    this.#finishLoading();

    // A response that arrives after the plan was cleared or became unavailable is stale
    if (!this.#planType || !this.#installmentsAllowed) {
      this.#clearPreview();
      return;
    }

    const announcement = this.previewTarget.querySelector("[data-recurring-form-announcement]");
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

  get #planType() {
    const checked = this.element.querySelector('input[name="recurrence[plan_type]"]:checked');
    return checked ? checked.value : "";
  }

  get #installmentsAllowed() {
    if (this.#planType !== "installments") return true;
    return this.hasInstallmentsOptionTarget && !this.installmentsOptionTarget.querySelector("input").disabled;
  }

  #watched(name) {
    return (
      typeof name === "string" &&
      (name.startsWith("recurrence[") || ["entry[account_id]", "entry[amount]", "entry[currency]", "entry[date]"].includes(name))
    );
  }

  #toggleCreditOnlyNote(visible) {
    const note = this.element.querySelector("[data-recurring-form-note]");
    if (note) note.hidden = !visible;
  }

  get #form() {
    return this.element.closest("form") || this.element;
  }

  #applyType() {
    const type = this.#planType;

    this.fieldsTargets.forEach((group) => {
      const active = group.dataset.planType === type;
      group.hidden = !active;
      group.querySelectorAll("input, select").forEach((input) => {
        input.disabled = !active;
      });
    });

    if (this.hasReviewTarget) this.reviewTarget.disabled = type === "";
  }

  #syncInstallmentsOption() {
    if (!this.hasInstallmentsOptionTarget) return;

    const accountId = this.accountIdValue || this.#formValue("entry[account_id]");
    const isCreditCard = this.creditAccountIdsValue.includes(accountId);
    const radio = this.installmentsOptionTarget.querySelector("input");

    this.installmentsOptionTarget.hidden = !isCreditCard;
    radio.disabled = !isCreditCard;

    if (isCreditCard) this.#toggleCreditOnlyNote(false);

    if (!isCreditCard && radio.checked) {
      this.element.querySelector('input[name="recurrence[plan_type]"][value=""]').checked = true;
      this.#applyType();
      this.#clearPreview();
      this.#toggleCreditOnlyNote(true);
      this.#announce(this.creditOnlyTextValue);
    }
  }

  #loadPreview() {
    const url = new URL(this.previewUrlValue, window.location.origin);
    const data = new FormData(this.#form);

    [
      "entry[account_id]",
      "entry[amount]",
      "entry[currency]",
      "entry[date]",
      "recurrence[plan_type]",
      "recurrence[total_payments]",
      "recurrence[start_date]",
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

  #formValue(name) {
    const field = this.#form.elements.namedItem(name);
    return field ? field.value : "";
  }

  // Same rule as Ruby's Date#next_month: Jan 31 -> Feb 28
  #addOneMonth(isoDate) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(isoDate || "");
    if (!match) return null;

    const year = Number(match[1]);
    const month = Number(match[2]);
    const day = Number(match[3]);
    const targetYear = month === 12 ? year + 1 : year;
    const targetMonth = month === 12 ? 1 : month + 1;
    const lastDay = new Date(Date.UTC(targetYear, targetMonth, 0)).getUTCDate();
    const pad = (n) => String(n).padStart(2, "0");

    return `${targetYear}-${pad(targetMonth)}-${pad(Math.min(day, lastDay))}`;
  }
}
