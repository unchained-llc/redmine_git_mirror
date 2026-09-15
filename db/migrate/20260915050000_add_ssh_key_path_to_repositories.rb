class AddSshKeyPathToRepositories < ActiveRecord::Migration[6.1]
  def change
    add_column :repositories, :ssh_key_path, :string
  end
end
