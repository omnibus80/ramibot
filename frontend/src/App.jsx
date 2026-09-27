import { useEffect, useState } from 'react'
import useStore from './store'
import Sidebar from './components/Sidebar'
import ChatPanel from './components/ChatPanel'
import SettingsModal from './components/SettingsModal'
import DockerTerminal from './components/DockerTerminal'
import MatrixRain from './components/MatrixRain'
import OsirisPanel from './components/OsirisPanel'

function App() {
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [osirisOpen, setOsirisOpen] = useState(false)
  const { loadSettings, fetchConversations, fetchProviders, teamMode, terminalCount, removeTerminal } = useStore()

  useEffect(() => {
    loadSettings()
    fetchConversations()
    fetchProviders()
  }, [])

  useEffect(() => {
    document.documentElement.setAttribute('data-team', teamMode)
  }, [teamMode])

  return (
    <div style={{
      display: 'flex',
      height: '100vh',
      minHeight: '100dvh',
      width: '100%',
      background: 'var(--bg)',
      color: 'var(--t1)',
      fontFamily: 'var(--font-mono)',
      overflow: 'hidden',
      boxSizing: 'border-box',
    }}>
      <Sidebar onOpenSettings={() => setSettingsOpen(true)} onOpenOsiris={() => setOsirisOpen(true)} />

      <div
        style={{
          flex: 1,
          display: 'flex',
          minWidth: 0,
          position: 'relative',
          width: '100%',
          minHeight: 0,
          overflow: 'hidden',
        }}
      >
        <MatrixRain />

        <div style={{
          display: 'flex',
          flexDirection: 'column',
          minWidth: 0,
          flex: terminalCount === 0 ? '1' : '0 0 60%',
          position: 'relative',
          zIndex: 1,
          minHeight: 0,
          overflow: 'hidden',
        }}>
          {osirisOpen ? <OsirisPanel onClose={() => setOsirisOpen(false)} /> : <ChatPanel />}
        </div>

        {terminalCount >= 1 && (
          <div style={{
            flex: '0 0 40%',
            display: 'flex',
            flexDirection: 'column',
            padding: '0.75rem',
            gap: '0.75rem',
            boxSizing: 'border-box',
            position: 'relative',
            zIndex: 1,
            minHeight: 0,
            overflow: 'hidden',
          }}>
            <div style={{ flex: 1, minHeight: 0, overflow: 'hidden' }}>
              <DockerTerminal terminalId={1} onClose={() => removeTerminal()} />
            </div>
            {terminalCount >= 2 && (
              <div style={{ flex: 1, minHeight: 0, overflow: 'hidden' }}>
                <DockerTerminal terminalId={2} onClose={() => removeTerminal()} />
              </div>
            )}
          </div>
        )}
      </div>

      {settingsOpen && <SettingsModal onClose={() => setSettingsOpen(false)} />}
    </div>
  )
}

export default App
