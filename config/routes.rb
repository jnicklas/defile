if Refile.automount
  Rails.application.routes.draw do
    mount Refile.app, at: Refile.mount_point, as: :refile_app, via: [:get, :post, :head, :options]
  end
end
