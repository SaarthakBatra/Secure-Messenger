const { initKeypair } = require('./keypair');

module.exports = function(app) {
  initKeypair().catch(err => console.error(err));
  app.use('/dev', require('./router'));
  app.use('/dev', require('./routes'));
};
