const gamePath = /^\/(play|kazhutha|rummy|game-28|teen-patti|blackjack|bluff|tambola|wildcard)\/?$/i;
if (gamePath.test(location.pathname)) {
  const website = document.getElementById("website");
  website.hidden = true;
  const bootstrap = document.createElement("script");
  bootstrap.src = "/flutter_bootstrap.js";
  bootstrap.onerror = () => { website.hidden = false; };
  document.body.append(bootstrap);
}
