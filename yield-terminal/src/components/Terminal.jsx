import React, { useState, useEffect, useRef, useCallback } from 'react'
import './Terminal.css'
import { COMMAND_LIST, COMMAND_METADATA } from '../commands/metadata'
import { useTerminalCommands } from '../hooks/useTerminalCommands'

const INITIAL_OUTPUT = [
  { type: 'info', text: 'Welcome to Yield Terminal' },
  { type: 'info', text: 'Type "help" to see available commands' },
]

export default function Terminal({ contracts, isConnected, network, loading, setLoading, onStatusUpdate }) {
  const [output, setOutput] = useState(() => INITIAL_OUTPUT)
  const [input, setInput] = useState('')
  const outputEndRef = useRef(null)

  const addOutput = useCallback((type, text) => {
    setOutput((prev) => [...prev, { type, text, timestamp: Date.now() }])
  }, [])

  const terminalCommands = useTerminalCommands({ contracts, addOutput, setLoading, onStatusUpdate })

  useEffect(() => {
    outputEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [output])

  const showHelp = useCallback(() => {
    const helpText = COMMAND_LIST.map(
      (cmd) => `  ${cmd.usage.padEnd(25)} - ${cmd.description}`,
    ).join('\n')
    addOutput(
      'info',
      `Available Commands:\n\n${helpText}\n\nExamples:\n  deposit 1000           - Deposit 1000 USDT0\n  auto smart             - Auto-deposit with smart allocation\n  harvest 75             - Harvest yield, compound 75%\n  check-op               - Check if operations can be performed\n  config                 - Show vault configuration\n  best-strategy          - Get best yield strategy`,
    )
  }, [addOutput])

  const handleCommand = useCallback(
    async (command) => {
      const trimmed = command.trim()
      if (!trimmed) return

      addOutput('command', trimmed)

      const [cmd, ...args] = trimmed.split(/\s+/)
      const lower = cmd.toLowerCase()

      if (lower === 'help') {
        showHelp()
        return
      }

      if (lower === 'clear') {
        setOutput(INITIAL_OUTPUT)
        return
      }

      const metadata = COMMAND_METADATA[lower]
      if (!metadata) {
        addOutput('error', `Unknown command: ${lower}. Type 'help' for available commands.`)
        return
      }

      if (metadata.requiresConnection && (!isConnected || !contracts)) {
        addOutput('error', 'Please connect your wallet first')
        return
      }

      // Check network requirements
      if (metadata.requiresNetwork) {
        if (network !== metadata.requiresNetwork) {
          addOutput('error', `This command requires ${metadata.requiresNetwork} network. Current: ${network}`)
          return
        }
      }

      const commandEntry = terminalCommands[lower]
      if (!commandEntry || typeof commandEntry.handler !== 'function') {
        addOutput('error', 'Command not available in current context')
        return
      }

      try {
        await commandEntry.handler({ args })
      } catch (error) {
        addOutput('error', `Command failed: ${error.message}`)
        setLoading(false)
      }
    },
    [addOutput, contracts, isConnected, setLoading, showHelp, terminalCommands],
  )

  const handleKeyPress = useCallback(
    (e) => {
      if (e.key === 'Enter' && input.trim()) {
        handleCommand(input)
        setInput('')
      }
    },
    [handleCommand, input],
  )

  return (
    <div className="terminal-container">
      <div className="terminal-window">
        <div className="terminal-output">
          {output.map((line, idx) => (
            <div key={idx} className={`terminal-line ${line.type}`}>
              <span className="prompt">yield@terminal:~$</span>
              <span className="command">{line.text}</span>
            </div>
          ))}
          <div ref={outputEndRef} />
        </div>
        <div className="terminal-input-container">
          <span className="prompt">yield@terminal:~$</span>
          <input
            type="text"
            className="terminal-input"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyPress={handleKeyPress}
            disabled={loading}
            autoFocus
          />
        </div>
      </div>
    </div>
  )
}

