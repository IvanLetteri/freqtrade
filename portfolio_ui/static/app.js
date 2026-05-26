function linesToArray(text) {
  return text
    .split("\n")
    .map((x) => x.trim())
    .filter(Boolean);
}

function arrayToLines(arr) {
  return (arr || []).join("\n");
}

async function loadHealth() {
  const pill = document.getElementById("health-pill");
  const box = document.getElementById("health-json");

  try {
    const response = await fetch("/api/health");
    const data = await response.json();

    pill.textContent = "Backend online";
    pill.classList.remove("error");
    pill.classList.add("ok");
    box.textContent = JSON.stringify(data, null, 2);
  } catch (error) {
    pill.textContent = "Backend offline";
    pill.classList.remove("ok");
    pill.classList.add("error");
    box.textContent = String(error);
  }
}

async function loadConfig() {
  const box = document.getElementById("config-json");

  try {
    const response = await fetch("/api/config");
    const data = await response.json();
    box.textContent = JSON.stringify(data, null, 2);

    const tu = data.tradfi_universe?.data?.tradfi_universe;
    if (tu) {
      document.getElementById("enabled").checked = !!tu.enabled;
      document.getElementById("asset_classes").value = arrayToLines(tu.asset_classes);
      document.getElementById("symbols").value = arrayToLines(tu.symbols);
      document.getElementById("excluded_symbols").value = arrayToLines(tu.excluded_symbols);
      document.getElementById("min_universe_size").value = tu.min_universe_size ?? 1;
    }
  } catch (error) {
    box.textContent = `Errore caricando la config: ${error}`;
  }
}

async function saveTradfiUniverse(event) {
  event.preventDefault();

  const resultBox = document.getElementById("save-result");

  const payload = {
    enabled: document.getElementById("enabled").checked,
    asset_classes: linesToArray(document.getElementById("asset_classes").value),
    symbols: linesToArray(document.getElementById("symbols").value),
    excluded_symbols: linesToArray(document.getElementById("excluded_symbols").value),
    min_universe_size: Number(document.getElementById("min_universe_size").value || 1),
  };

  try {
    const response = await fetch("/api/config/tradfi_universe", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const data = await response.json();
    resultBox.textContent = JSON.stringify(data, null, 2);

    if (!response.ok) {
      throw new Error(data.detail || "Salvataggio fallito");
    }

    await loadConfig();
  } catch (error) {
    resultBox.textContent = `Errore di salvataggio: ${error}`;
  }
}

async function boot() {
  await loadHealth();
  await loadConfig();

  const form = document.getElementById("tradfi-form");
  form.addEventListener("submit", saveTradfiUniverse);
}

boot();