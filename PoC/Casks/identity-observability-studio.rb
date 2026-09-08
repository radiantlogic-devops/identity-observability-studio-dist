cask "identity-observability-studio" do
  version "2026.08.24"
  sha256 "b78276de62e60348f87e51013b86aca7223cdc767d42a5dbd16471336d996f9c"

  url "https://github.com/radiantlogic-devops/identity-observability-studio-dist/releases/download/v#{version}/IdentityObservabilityStudio-#{version}-macos-arm64.zip",
      verified: "github.com/radiantlogic-devops/"

  # Pour tester en local sans passer par la release, commenter l'url ci-dessus
  # et decommenter celle-ci :
  #
  #   url "file:///chemin/vers/dist/IdentityObservabilityStudio-#{version}-macos-arm64.zip"

  name "Identity Observability Studio"
  desc "Eclipse-based Studio for the Radiant Logic Identity Observability Platform"
  homepage "https://www.radiantlogic.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :big_sur
  depends_on arch: :arm64

  # Le JRE Temurin 21 est embarque dans Contents/Eclipse/jre et reference par
  # -vm dans igrcanalytics.ini : aucune dependance Java externe, et le Studio
  # demarre depuis le Finder ou le PATH est minimal.
  app "Identity Observability Studio.app"

  uninstall quit: "com.brainwave.igrcanalytics.product"

  # Uniquement des chemins portees par CFBundleIdentifier, donc propres a ce
  # produit. Volontairement absents :
  #   ~/.eclipse_keyring, ~/.eclipse/, ~/eclipse-workspace
  # Ce sont les emplacements generiques d'Eclipse, partages avec toute autre
  # installation Eclipse du poste : les zapper detruirait les donnees d'un
  # autre produit. Le Studio ecrit sa zone de configuration OSGi a l'interieur
  # de son propre bundle, donc il ne laisse rien d'autre derriere lui.
  zap trash: [
    "~/Library/Caches/com.brainwave.igrcanalytics.product",
    "~/Library/Preferences/com.brainwave.igrcanalytics.product.plist",
    "~/Library/Saved Application State/com.brainwave.igrcanalytics.product.savedState",
  ]

  caveats <<~CAVEATS
    L'application n'est pas notarisee par Apple. Homebrew pose l'attribut de
    quarantaine sur tout ce qu'il telecharge et, depuis Homebrew 5, ne permet
    plus a un cask de le retirer. Gatekeeper refusera donc le premier
    lancement tant que vous ne l'aurez pas approuvee explicitement.

    Apres verification de la provenance, levez la quarantaine :

      xattr -dr com.apple.quarantine "/Applications/Identity Observability Studio.app"

    Si la commande repond "Operation not permitted", accordez a votre terminal
    la permission "Gestion de l'app" dans Reglages Systeme > Confidentialite
    et securite, puis relancez-la.

    Alternative sans terminal : lancez l'app une fois, laissez macOS la
    bloquer, puis Reglages Systeme > Confidentialite et securite >
    "Ouvrir quand meme".
  CAVEATS
end
