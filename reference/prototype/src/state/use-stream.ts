import { useCallback, useEffect, useRef, useState } from "react"

export type StreamStatus = "idle" | "thinking" | "streaming" | "done"

// Simulated streaming: a short "thinking" beat, then the text word by word.
export function useStream(thinkMs = 800, wordMs = 38) {
  const [text, setText] = useState("")
  const [status, setStatus] = useState<StreamStatus>("idle")
  const timers = useRef<number[]>([])
  const clear = useCallback(() => {
    timers.current.forEach((t) => {
      clearTimeout(t)
      clearInterval(t)
    })
    timers.current = []
  }, [])
  useEffect(() => clear, [clear])

  const start = useCallback(
    (full: string) => {
      clear()
      setText("")
      setStatus("thinking")
      const tokens = full.split(/(\s+)/)
      timers.current.push(
        window.setTimeout(() => {
          setStatus("streaming")
          let i = 0
          const id = window.setInterval(() => {
            i += 2
            setText(tokens.slice(0, i).join(""))
            if (i >= tokens.length) {
              clearInterval(id)
              setStatus("done")
            }
          }, wordMs)
          timers.current.push(id)
        }, thinkMs),
      )
    },
    [clear, thinkMs, wordMs],
  )
  const reset = useCallback(() => {
    clear()
    setText("")
    setStatus("idle")
  }, [clear])
  return { text, status, start, reset }
}
