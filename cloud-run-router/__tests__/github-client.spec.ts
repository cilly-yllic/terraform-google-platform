import { describe, it, expect } from 'vitest'
import { toWireClientPayload, type DispatchPayload } from '../src/github-client.js'

// WHY: environments / labels を wire 上で compact JSON 文字列として送ることが
// 受信側 (Action B) の `$GITHUB_OUTPUT` 書き込み崩壊 (Invalid format) を防ぐ前提。
// この shape が崩れると pretty-print 改行が混入して再発するため回帰テストで固定する。
describe('toWireClientPayload', () => {
  const base: DispatchPayload = {
    service: 'my-svc',
    environments: ['dev-001', 'dev-002'],
    labels: ['^tier:dev$'],
    run_id: 'run-abc',
    workspace_name: 'project-factory-my-svc',
    source_repo: 'owner/repo',
  }

  it('serializes environments / labels to compact (single-line) JSON strings', () => {
    const wire = toWireClientPayload(base)
    expect(wire.environments).toBe('["dev-001","dev-002"]')
    expect(wire.labels).toBe('["^tier:dev$"]')
    // 単一行であること (pretty-print の改行が混ざっていない)
    expect(String(wire.environments)).not.toContain('\n')
    expect(String(wire.labels)).not.toContain('\n')
  })

  it('keeps scalar fields untouched', () => {
    const wire = toWireClientPayload(base)
    expect(wire.service).toBe('my-svc')
    expect(wire.run_id).toBe('run-abc')
    expect(wire.workspace_name).toBe('project-factory-my-svc')
    expect(wire.source_repo).toBe('owner/repo')
  })

  it('serializes empty arrays to "[]" (not "" / undefined)', () => {
    const wire = toWireClientPayload({ ...base, environments: [], labels: [] })
    expect(wire.environments).toBe('[]')
    expect(wire.labels).toBe('[]')
  })
})
