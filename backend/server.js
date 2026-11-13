const config = require('./src/config/env');
const app = require('./src/app');

app.listen(config.port, () => {
  console.log(`Server running on http://localhost:${config.port} (${config.nodeEnv})`);
});