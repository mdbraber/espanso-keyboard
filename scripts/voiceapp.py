"""Stands in for the Hex app's Listener in the simulator, which can't record: holds the microphone lock, answers the
keyboard's start with listening and a voice's worth of levels, finish with what was "heard", and stop by letting go of
the microphone. scripts/voiceapp.py <simulator id> <App Group container>"""
import fcntl, json, math, os, struct, subprocess, sys, threading

simulator, group = sys.argv[1:3]
prefix = "com.shahidy.hexkeyboard.dictation"
os.makedirs(f"{group}/Library", exist_ok=True)


def notify(*arguments):
    return subprocess.Popen(["xcrun", "simctl", "spawn", simulator, "notifyutil", *arguments], stdout=subprocess.DEVNULL)


def publish(state, heard=None):
    with open(f"{group}/Library/dictation.json", "w") as file:
        json.dump({"state": state, **({"heard": heard} if heard else {})}, file)
    notify("-p", prefix).wait()


def speak(stop):
    step = 0
    while not stop.is_set():
        level = 0.002 + 0.12 * abs(math.sin(step * 0.9) * math.sin(step * 0.37 + 1))
        bits = struct.unpack("<I", struct.pack("<f", level))[0]
        notify("-s", f"{prefix}.level", str(bits)).wait()
        notify("-p", f"{prefix}.level").wait()
        step += 1
        stop.wait(0.1)


lock = open(f"{group}/Library/mic.lock", "w")
fcntl.flock(lock, fcntl.LOCK_EX)
started = notify("-1", f"{prefix}.start")
publish("idle")
started.wait()
finished = notify("-1", f"{prefix}.finish")
publish("listening")
stop = threading.Event()
voice = threading.Thread(target=speak, args=(stop,))
voice.start()
finished.wait()
stop.set()
voice.join()
stopped = notify("-1", f"{prefix}.stop")
publish("transcribing")
publish("idle", "hello from the mic")
stopped.wait()
fcntl.flock(lock, fcntl.LOCK_UN)
lock.close()
notify("-p", prefix).wait()
