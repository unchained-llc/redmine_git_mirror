class AddWebhookSecretToRepositories < ActiveRecord::Migration[6.1]
  def change
    add_column :repositories, :webhook_secret, :string
  end
end
