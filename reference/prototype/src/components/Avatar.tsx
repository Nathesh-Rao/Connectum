export function Avatar({ name, tone = "sage", photo = false }: any) {
  return (
    <span className={`avatar ${tone} ${photo ? "photo" : ""}`}>
      {photo ? (
        <img
          src={`https://i.pravatar.cc/100?img=${
            name === "Priya Sharma" ? 47 : 12
          }`}
          alt={name}
        />
      ) : (
        name
      )}
      <i />
    </span>
  )
}
