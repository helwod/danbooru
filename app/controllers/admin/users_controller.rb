# frozen_string_literal: true

module Admin
  class UsersController < ApplicationController
    def edit
      @user = authorize User.find(params[:id]), :promote?
    end

    def update
      @user = authorize User.find(params[:id]), :promote?

      @level = params.dig(:user, :level)

      @user.promote_to!(@level, CurrentUser.user)

      redirect_to edit_admin_user_path(@user), notice: I18n.t("admin.flash.user_updated")
    end
  end
end
