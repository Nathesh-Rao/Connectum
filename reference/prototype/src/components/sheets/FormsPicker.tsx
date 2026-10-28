import { useApp } from "../../app-state"
import { forms, MY_SUBMISSIONS } from "../../data/forms"
import { Button } from "../Button"
import { Icon } from "../Icon"
import { Landing, Rise } from "../Landing"

// Searchable list of forms: a Recent row, then everything. Opened from the
// Forms button in the composer.
export function FormsPicker() {
  const { formsQuery, setFormsQuery, recentForms, openForm } = useApp()
  const q = formsQuery.trim().toLowerCase()
  const list = forms.filter((f) => f.name.toLowerCase().includes(q))
  const showMine = !q || MY_SUBMISSIONS.toLowerCase().includes(q)
  return (
    <Landing id="forms-sheet">
      <div className="forms-search">
        <Icon name="search" />
        <input
          value={formsQuery}
          onChange={(e) => setFormsQuery(e.target.value)}
          placeholder="Search forms"
        />
      </div>
      {!q && (
        <Rise index={1}>
          <div className="forms-label">Recent</div>
          <div className="forms-recent">
            {recentForms.map((name) => (
              <Button
                key={name}
                className="chip"
                onClick={() => openForm(name)}
              >
                {name}
              </Button>
            ))}
          </div>
        </Rise>
      )}
      <div className="forms-list">
        {!q && <div className="forms-label">All forms</div>}
        {list.map((f, i) => (
          <Button
            key={f.name}
            className="setting"
            landing={2 + i}
            onClick={() => openForm(f.name)}
          >
            <span className="form-row-label">
              <Icon name="file" />
              {f.name}
            </span>
            <Icon name="arrow" />
          </Button>
        ))}
        {showMine && (
          <Button
            className="setting"
            landing={2 + list.length}
            onClick={() => openForm(MY_SUBMISSIONS)}
          >
            <span className="form-row-label">
              <Icon name="grid" />
              {MY_SUBMISSIONS}
            </span>
            <Icon name="arrow" />
          </Button>
        )}
        {!list.length && !showMine && <p className="empty">No forms found.</p>}
      </div>
    </Landing>
  )
}
