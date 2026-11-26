import { useEffect, useState, type FormEvent } from 'react'
import {
  Alert,
  AppBar,
  Box,
  Button,
  Card,
  CardContent,
  CardHeader,
  Chip,
  CircularProgress,
  Container,
  IconButton,
  InputAdornment,
  Snackbar,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Toolbar,
  Typography,
} from '@mui/material'
import PersonAddIcon from '@mui/icons-material/PersonAdd'
import SchoolIcon from '@mui/icons-material/School'
import Visibility from '@mui/icons-material/Visibility'
import VisibilityOff from '@mui/icons-material/VisibilityOff'
import RefreshIcon from '@mui/icons-material/Refresh'

type Student = { id: number; name: string; createdAt: string }
type Toast = { severity: 'success' | 'error'; text: string } | null

const API = '/api/students'

function App() {
  const [students, setStudents] = useState<Student[]>([])
  const [listLoading, setListLoading] = useState(true)
  const [name, setName] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [saving, setSaving] = useState(false)
  const [toast, setToast] = useState<Toast>(null)

  async function loadStudents() {
    setListLoading(true)
    try {
      const res = await fetch(API)
      setStudents(await res.json())
    } catch {
      setToast({ severity: 'error', text: 'Could not load students' })
    } finally {
      setListLoading(false)
    }
  }

  useEffect(() => {
    fetch(API)
      .then((res) => res.json())
      .then(setStudents)
      .catch(() => setToast({ severity: 'error', text: 'Could not load students' }))
      .finally(() => setListLoading(false))
  }, [])

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      const res = await fetch(API, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, password }),
      })
      const data = await res.json()
      if (!res.ok) {
        const msg = Array.isArray(data.message) ? data.message.join(', ') : data.message
        throw new Error(msg || 'Register failed')
      }
      setToast({ severity: 'success', text: `Registered ${data.name}` })
      setName('')
      setPassword('')
      await loadStudents()
    } catch (err) {
      setToast({ severity: 'error', text: (err as Error).message })
    } finally {
      setSaving(false)
    }
  }

  const passwordTooShort = password.length > 0 && password.length < 6

  return (
    <>
      <AppBar position="static" elevation={1}>
        <Toolbar>
          <SchoolIcon sx={{ mr: 1.5 }} />
          <Typography variant="h6" component="h1">
            Student Register
          </Typography>
        </Toolbar>
      </AppBar>

      <Container maxWidth="md" sx={{ py: 4 }}>
        <Stack spacing={3}>
          <Card elevation={2}>
            <CardHeader title="Register a student" subheader="Enter a name and password" />
            <CardContent>
              <Box component="form" onSubmit={handleSubmit} noValidate>
                <Stack spacing={2.5}>
                  <TextField
                    label="Name"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    required
                    fullWidth
                    autoComplete="username"
                  />
                  <TextField
                    label="Password"
                    type={showPassword ? 'text' : 'password'}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    fullWidth
                    autoComplete="new-password"
                    error={passwordTooShort}
                    helperText="At least 6 characters"
                    slotProps={{
                      input: {
                        endAdornment: (
                          <InputAdornment position="end">
                            <IconButton
                              aria-label={showPassword ? 'Hide password' : 'Show password'}
                              onClick={() => setShowPassword((v) => !v)}
                              edge="end"
                            >
                              {showPassword ? <VisibilityOff /> : <Visibility />}
                            </IconButton>
                          </InputAdornment>
                        ),
                      },
                    }}
                  />
                  <Button
                    type="submit"
                    variant="contained"
                    size="large"
                    startIcon={saving ? <CircularProgress size={20} color="inherit" /> : <PersonAddIcon />}
                    disabled={saving || !name.trim() || password.length < 6}
                  >
                    {saving ? 'Saving…' : 'Register'}
                  </Button>
                </Stack>
              </Box>
            </CardContent>
          </Card>

          <Card elevation={2}>
            <CardHeader
              title={
                <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                  <span>All students</span>
                  <Chip label={students.length} size="small" color="primary" />
                </Stack>
              }
              action={
                <IconButton aria-label="Refresh" onClick={loadStudents}>
                  <RefreshIcon />
                </IconButton>
              }
            />
            <CardContent sx={{ pt: 0 }}>
              {listLoading ? (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                  <CircularProgress />
                </Box>
              ) : students.length === 0 ? (
                <Typography color="text.secondary" sx={{ py: 2, textAlign: 'center' }}>
                  No students yet.
                </Typography>
              ) : (
                <TableContainer>
                  <Table size="small">
                    <TableHead>
                      <TableRow>
                        <TableCell>ID</TableCell>
                        <TableCell>Name</TableCell>
                        <TableCell>Registered</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {students.map((s) => (
                        <TableRow key={s.id} hover>
                          <TableCell>{s.id}</TableCell>
                          <TableCell>{s.name}</TableCell>
                          <TableCell>{new Date(s.createdAt).toLocaleString()}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </TableContainer>
              )}
            </CardContent>
          </Card>
        </Stack>
      </Container>

      <Snackbar
        open={toast !== null}
        autoHideDuration={4000}
        onClose={() => setToast(null)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      >
        {toast ? (
          <Alert severity={toast.severity} variant="filled" onClose={() => setToast(null)}>
            {toast.text}
          </Alert>
        ) : undefined}
      </Snackbar>
    </>
  )
}

export default App
