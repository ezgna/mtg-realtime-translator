const LANGUAGES = [
  ["ja", "日本語"],
  ["en", "English"],
  ["es", "Español"],
  ["pt", "Português"],
  ["fr", "Français"],
  ["it", "Italiano"],
  ["de", "Deutsch"],
  ["zh", "中文"],
  ["ko", "한국어"],
  ["id", "Bahasa Indonesia"],
  ["vi", "Tiếng Việt"],
];

const state = {
  pc: null,
  events: null,
  localStream: null,
  audioContext: null,
  meterSource: null,
  meterAnalyser: null,
  meterFrame: null,
  startedAt: null,
  closedResolve: null,
  phase: "idle",
};

const els = {
  language: document.querySelector("#languageSelect"),
  input: document.querySelector("#inputSelect"),
  output: document.querySelector("#outputSelect"),
  echo: document.querySelector("#echoCancel"),
  noise: document.querySelector("#noiseSuppress"),
  gain: document.querySelector("#autoGain"),
  refresh: document.querySelector("#refreshButton"),
  teamsSelfPreset: document.querySelector("#teamsSelfPresetButton"),
  session: document.querySelector("#sessionButton"),
  clear: document.querySelector("#clearButton"),
  statusText: document.querySelector("#statusText"),
  statusPill: document.querySelector("#statusPill"),
  connection: document.querySelector("#connectionLabel"),
  level: document.querySelector("#levelFill"),
  source: document.querySelector("#sourceTranscript"),
  translation: document.querySelector("#translationTranscript"),
  remoteAudio: document.querySelector("#remoteAudio"),
};

function setSessionControlsEnabled(enabled) {
  els.language.disabled = !enabled;
  els.input.disabled = !enabled;
  els.echo.disabled = !enabled;
  els.noise.disabled = !enabled;
  els.gain.disabled = !enabled;
  els.teamsSelfPreset.disabled = !enabled;
}

for (const [id, label] of LANGUAGES) {
  const option = document.createElement("option");
  option.value = id;
  option.textContent = `${label} · ${id}`;
  els.language.append(option);
}

function setStatus(text, mode = "idle") {
  els.statusText.textContent = text;
  els.statusPill.dataset.mode = mode;
}

function setSessionButton(phase) {
  state.phase = phase;
  els.session.dataset.phase = phase;
  if (phase === "connecting") {
    els.session.textContent = "Connecting";
    els.session.disabled = true;
    return;
  }
  if (phase === "live") {
    els.session.textContent = "Stop";
    els.session.disabled = false;
    return;
  }
  if (phase === "stopping") {
    els.session.textContent = "Stopping";
    els.session.disabled = true;
    return;
  }
  els.session.textContent = "Start";
  els.session.disabled = false;
}

function appendText(target, text) {
  target.textContent += text;
  target.scrollTop = target.scrollHeight;
}

function appendBreak(target) {
  if (target.textContent && !target.textContent.endsWith("\n\n")) {
    target.textContent += "\n\n";
  }
  target.scrollTop = target.scrollHeight;
}

function extractClientSecret(payload) {
  return (
    payload?.value ||
    payload?.client_secret?.value ||
    payload?.clientSecret?.value ||
    payload?.secret?.value
  );
}

function findDeviceOption(select, pattern) {
  return [...select.options].find((option) => pattern.test(option.textContent || ""));
}

function selectPreferredInput() {
  const selected = els.input.selectedOptions[0];
  if (selected?.value && !/blackhole/i.test(selected.textContent || "")) {
    return;
  }

  const realMic = [...els.input.options].find((option) => {
    const label = option.textContent || "";
    return option.value && label && !/blackhole/i.test(label);
  });
  els.input.value = realMic?.value || "";
}

async function unlockDeviceLabels() {
  const devices = await navigator.mediaDevices.enumerateDevices();
  if (devices.some((device) => device.label)) {
    return;
  }

  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  for (const track of stream.getTracks()) {
    track.stop();
  }
}

async function refreshDevices() {
  if (!navigator.mediaDevices?.enumerateDevices) {
    return;
  }
  const devices = await navigator.mediaDevices.enumerateDevices();
  const currentInput = els.input.value;
  const currentOutput = els.output.value;

  els.input.replaceChildren(new Option("System default", ""));
  els.output.replaceChildren(new Option("System default", ""));

  for (const device of devices) {
    if (device.kind === "audioinput") {
      els.input.append(new Option(device.label || `Microphone ${els.input.length}`, device.deviceId));
    }
    if (device.kind === "audiooutput") {
      els.output.append(new Option(device.label || `Speaker ${els.output.length}`, device.deviceId));
    }
  }

  if ([...els.input.options].some((option) => option.value === currentInput)) {
    els.input.value = currentInput;
  }
  if ([...els.output.options].some((option) => option.value === currentOutput)) {
    els.output.value = currentOutput;
  }

  els.output.disabled = typeof els.remoteAudio.setSinkId !== "function";
}

async function applyTeamsSelfPreset() {
  if (state.pc) {
    return;
  }

  setStatus("Preparing", "working");
  els.connection.textContent = "Applying Teams preset";
  els.teamsSelfPreset.disabled = true;

  try {
    els.language.value = "en";
    els.echo.checked = true;
    els.noise.checked = true;
    els.gain.checked = true;

    await unlockDeviceLabels();
    await refreshDevices();
    selectPreferredInput();

    const blackHole =
      findDeviceOption(els.output, /blackhole.*2ch|2ch.*blackhole/i) ||
      findDeviceOption(els.output, /blackhole/i);
    if (!blackHole) {
      throw new Error("BlackHole の出力デバイスが見つかりません");
    }
    if (typeof els.remoteAudio.setSinkId !== "function") {
      throw new Error("このブラウザではスピーカー出力先を切り替えられません");
    }

    els.output.value = blackHole.value;
    await els.remoteAudio.setSinkId(blackHole.value);

    setStatus("Ready", "idle");
    els.connection.textContent = "Teams preset ready";
  } catch (error) {
    setStatus("Setup needed", "error");
    els.connection.textContent = "Teams preset needs setup";
    appendText(els.translation, `\n[Setup] ${error.message}\n`);
  } finally {
    els.teamsSelfPreset.disabled = false;
  }
}

function buildAudioConstraints() {
  const audio = {
    echoCancellation: els.echo.checked,
    noiseSuppression: els.noise.checked,
    autoGainControl: els.gain.checked,
  };
  if (els.input.value) {
    audio.deviceId = { exact: els.input.value };
  }
  return { audio };
}

function startMeter(stream) {
  stopMeter();
  const AudioContext = window.AudioContext || window.webkitAudioContext;
  if (!AudioContext) {
    return;
  }
  const context = new AudioContext();
  const source = context.createMediaStreamSource(stream);
  const analyser = context.createAnalyser();
  analyser.fftSize = 1024;
  source.connect(analyser);

  const samples = new Uint8Array(analyser.fftSize);
  const tick = () => {
    analyser.getByteTimeDomainData(samples);
    let sum = 0;
    for (const sample of samples) {
      const normalized = (sample - 128) / 128;
      sum += normalized * normalized;
    }
    const rms = Math.sqrt(sum / samples.length);
    els.level.style.width = `${Math.min(100, rms * 260)}%`;
    state.meterFrame = requestAnimationFrame(tick);
  };

  state.audioContext = context;
  state.meterSource = source;
  state.meterAnalyser = analyser;
  tick();
}

function stopMeter() {
  if (state.meterFrame) {
    cancelAnimationFrame(state.meterFrame);
    state.meterFrame = null;
  }
  if (state.audioContext) {
    state.audioContext.close();
    state.audioContext = null;
  }
  state.meterSource = null;
  state.meterAnalyser = null;
  els.level.style.width = "0%";
}

function handleRealtimeEvent(event) {
  if (event.type === "session.updated") {
    const language = event.session?.audio?.output?.language;
    if (language && els.language.value !== language) {
      els.language.value = language;
    }
    if (language) {
      els.connection.textContent = `language: ${language}`;
    }
    return;
  }
  if (event.type === "session.output_transcript.delta") {
    appendText(els.translation, event.delta || "");
    return;
  }
  if (event.type === "session.output_transcript.done") {
    appendBreak(els.translation);
    return;
  }
  if (event.type === "session.input_transcript.delta") {
    appendText(els.source, event.delta || "");
    return;
  }
  if (event.type === "session.input_transcript.done") {
    appendBreak(els.source);
    return;
  }
  if (event.type === "error") {
    const message = event.error?.message || JSON.stringify(event.error || event);
    appendText(els.translation, `\n[Error] ${message}\n`);
    setStatus("Error", "error");
    return;
  }
  if (event.type === "session.closed") {
    els.connection.textContent = "session closed";
    state.closedResolve?.();
  }
}

async function start() {
  if (state.pc) {
    return;
  }

  setStatus("Connecting", "working");
  els.connection.textContent = "Requesting microphone";
  setSessionButton("connecting");
  setSessionControlsEnabled(false);

  try {
    const sessionResponse = await fetch("/session", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ targetLanguage: els.language.value }),
    });
    const sessionPayload = await sessionResponse.json();
    if (!sessionResponse.ok) {
      throw new Error(sessionPayload.error || JSON.stringify(sessionPayload));
    }
    const clientSecret = extractClientSecret(sessionPayload);
    if (!clientSecret) {
      throw new Error("client secret not found in /session response");
    }

    const stream = await navigator.mediaDevices.getUserMedia(buildAudioConstraints());
    state.localStream = stream;
    startMeter(stream);
    await refreshDevices();

    if (els.output.value && typeof els.remoteAudio.setSinkId === "function") {
      await els.remoteAudio.setSinkId(els.output.value);
    }

    const pc = new RTCPeerConnection();
    state.pc = pc;
    state.startedAt = Date.now();

    pc.onconnectionstatechange = () => {
      els.connection.textContent = pc.connectionState;
      if (pc.connectionState === "connected") {
        setStatus("Live", "live");
        setSessionButton("live");
      } else if (pc.connectionState === "failed") {
        setStatus("Error", "error");
      }
    };

    pc.ontrack = ({ streams }) => {
      els.remoteAudio.srcObject = streams[0];
      els.remoteAudio.play().catch(() => {});
    };

    const events = pc.createDataChannel("oai-events");
    state.events = events;
    events.onopen = () => {
      els.connection.textContent = "data channel open";
    };
    events.onmessage = ({ data }) => {
      try {
        handleRealtimeEvent(JSON.parse(data));
      } catch (error) {
        appendText(els.translation, `\n[Event parse error] ${error.message}\n`);
      }
    };

    for (const track of stream.getAudioTracks()) {
      pc.addTrack(track, stream);
    }

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    const sdpResponse = await fetch("https://api.openai.com/v1/realtime/translations/calls", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${clientSecret}`,
        "Content-Type": "application/sdp",
      },
      body: offer.sdp,
    });
    const answerSdp = await sdpResponse.text();
    if (!sdpResponse.ok) {
      throw new Error(answerSdp);
    }

    await pc.setRemoteDescription({ type: "answer", sdp: answerSdp });
    setStatus("Live", "live");
    setSessionButton("live");
  } catch (error) {
    appendText(els.translation, `\n[Error] ${error.message}\n`);
    await stop({ preserveStatus: true });
    setStatus("Error", "error");
    setSessionButton("idle");
  } finally {
    if (state.pc) {
      setSessionButton("live");
    } else if (state.phase === "connecting") {
      setSessionButton("idle");
    }
    setSessionControlsEnabled(!state.pc);
  }
}

async function stop({ preserveStatus = false } = {}) {
  if (state.phase === "stopping") {
    return;
  }

  const hadSession = Boolean(state.pc || state.events || state.localStream);
  if (hadSession) {
    setSessionButton("stopping");
    if (!preserveStatus) {
      setStatus("Stopping", "working");
    }
  }

  for (const track of state.localStream?.getTracks() || []) {
    track.stop();
  }
  state.localStream = null;

  if (state.events?.readyState === "open") {
    try {
      const closed = new Promise((resolve) => {
        state.closedResolve = resolve;
      });
      state.events.send(JSON.stringify({ type: "session.close" }));
      await Promise.race([
        closed,
        new Promise((resolve) => setTimeout(resolve, 1500)),
      ]);
    } catch {
      // 終了時の flush は best effort。
    } finally {
      state.closedResolve = null;
    }
  }

  stopMeter();

  state.events?.close();
  state.events = null;
  state.pc?.close();
  state.pc = null;
  els.remoteAudio.srcObject = null;
  els.connection.textContent = "Disconnected";
  if (!preserveStatus) {
    setStatus("Idle", "idle");
  }
  setSessionButton("idle");
  setSessionControlsEnabled(true);
}

els.session.addEventListener("click", () => {
  if (state.pc) {
    stop();
    return;
  }
  start();
});
els.refresh.addEventListener("click", refreshDevices);
els.teamsSelfPreset.addEventListener("click", applyTeamsSelfPreset);
els.clear.addEventListener("click", () => {
  els.source.textContent = "";
  els.translation.textContent = "";
});
els.output.addEventListener("change", async () => {
  if (els.output.value && typeof els.remoteAudio.setSinkId === "function") {
    await els.remoteAudio.setSinkId(els.output.value);
  }
});

window.addEventListener("beforeunload", () => {
  stop();
});

refreshDevices().catch(() => {});
