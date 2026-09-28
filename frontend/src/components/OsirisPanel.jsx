import { X } from 'lucide-react'

function getOsirisUrl() {
  const configured = import.meta.env.VITE_OSIRIS_URL
  if (configured) return configured

  return '/osiris/'
}

function OsirisPanel({ onClose }) {
  const url = getOsirisUrl()

  return (
    <section style={{ display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0, background: 'var(--bg)' }}>
      <header style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '0.75rem', padding: '0.55rem 0.8rem', borderBottom: '1px solid var(--bd)', flexShrink: 0 }}>
        <span style={{ fontFamily: 'var(--font-display)', fontSize: '0.7rem', letterSpacing: '0.14em', color: 'rgb(var(--accent))' }}>
          OSIRIS // WORLD INTEL
        </span>
        <div style={{ display: 'flex', gap: '0.35rem' }}>
          <button onClick={onClose} title="Close Osiris" style={{ display: 'grid', placeItems: 'center', width: '1.8rem', height: '1.8rem', color: 'var(--t2)', background: 'transparent', border: '1px solid var(--bd)', cursor: 'pointer' }}>
            <X size={14} />
          </button>
        </div>
      </header>
      <iframe title="Osiris intelligence dashboard" src={url} style={{ flex: 1, width: '100%', minHeight: 0, border: 0, background: '#05060a' }} allow="fullscreen; geolocation" />
    </section>
  )
}

export default OsirisPanel