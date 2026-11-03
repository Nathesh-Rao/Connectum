const paths: Record<string, string> = {
  chat: "M4 4h16v12H9l-5 4z",
  search: "m20 20-5-5M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0",
  bell: "M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4",
  arrow: "m9 5 7 7-7 7",
  back: "m15 5-7 7 7 7",
  plus: "M12 5v14M5 12h14",
  file: "M6 3h8l4 4v14H6zM9 12h6M9 16h6",
  user: "M20 21v-3a5 5 0 0 0-5-5H9a5 5 0 0 0-5 5v3M16 6a4 4 0 1 1-8 0 4 4 0 0 1 8 0",
  chevron: "m7 10 5 5 5-5",
  send: "m3 3 19 9-19 9 4-9zM7 12h15",
  more: "M5 12h.01M12 12h.01M19 12h.01",
  check: "m5 12 4 4L19 6",
  grid: "M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z",
  workspace: "M3 5h18v14H3zM3 10h18M9 10v9M6 7.5h.01M9 7.5h.01",
  building:
    "M5 21V3h14v18M3 21h18M9 7h.01M15 7h.01M9 11h.01M15 11h.01M10 21v-5h4v5",
  briefcase: "M3 7h18v13H3zM8 7V4h8v3M3 12q9 5 18 0M10 13h4",
  people:
    "M16 21v-3a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v3M13 6a3 3 0 1 1-6 0 3 3 0 0 1 6 0M17 3a3 3 0 0 1 0 6M21 21v-3a4 4 0 0 0-3-4",
  university: "m2 9 10-6 10 6-10 6zM6 12v5q6 5 12 0v-5M22 9v8",
  hospital: "M4 21V5h16v16M2 21h20M10 21v-5h4v5M12 7v6M9 10h6",
  hash: "M9 3 7 21M17 3l-2 18M4 9h17M3 15h17",
  spark: "m12 3 3 6 6 3-6 3-3 6-3-6-6-3 6-3z",
  mic: "M9 4a3 3 0 0 1 6 0v8a3 3 0 0 1-6 0zM5 10v2a7 7 0 0 0 14 0v-2M12 19v3",
  attach: "m8 13 6-6a3 3 0 0 1 4 4l-8 8a5 5 0 0 1-7-7l9-9",
  copy: "M9 9h11v11H9zM5 15H4V4h11v1",
  refresh: "M20 11a8 8 0 0 0-14-4M4 4v4h4M4 13a8 8 0 0 0 14 4M20 20v-4h-4",
  thumbUp: "M7 11v9H4v-9zM7 11l4-8a2 2 0 0 1 2 2v4h6a2 2 0 0 1 2 2l-1 6a2 2 0 0 1-2 2H7",
  thumbDown: "M7 13V4H4v9zM7 13l4 8a2 2 0 0 0 2-2v-4h6a2 2 0 0 0 2-2l-1-6a2 2 0 0 0-2-2H7",
  clock: "M12 7v5l3 2M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0",
  edit: "M4 20h4L19 9l-4-4L4 16zM13 7l4 4",
  compose: "M11 4H5a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-6M17 3l4 4-9 9H8v-4z",
  pin: "M9 3h6l-1 6 3 3H7l3-3zM12 12v9",
  close: "M6 6l12 12M18 6 6 18",
  arrowUp: "M12 19V5M6 11l6-6 6 6",
  down: "M12 5v14M6 13l6 6 6-6",
  smile:
    "M8 14q4 5 8 0M8 8h.01M16 8h.01M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
}
export function Icon({ name = "chat" }: { name?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d={paths[name] || paths.chat} />
    </svg>
  )
}
