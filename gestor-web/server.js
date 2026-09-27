// Servidor minimo para Azure App Service: sirve el build de Vite (dist/).
// App Service inyecta el puerto en process.env.PORT.
import express from 'express'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const dir = path.dirname(fileURLToPath(import.meta.url))
const app = express()

app.use(express.static(path.join(dir, 'dist')))
// SPA: cualquier ruta no-archivo devuelve index.html
app.get(/.*/, (req, res) => {
  res.sendFile(path.join(dir, 'dist', 'index.html'))
})

const port = process.env.PORT || 8080
app.listen(port, () => console.log(`gestor-web en puerto ${port}`))
