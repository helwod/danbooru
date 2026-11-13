# frozen_string_literal: true

module Maintenance
  module User
    class CountFixesController < ApplicationController
      def new
        @user = authorize CurrentUser.user, :fix_counts?
      end

      def create
        @user = authorize CurrentUser.user, :fix_counts?
        CurrentUser.user.refresh_counts!
        flash[:notice] = I18n.t("maintenance.flash.counts_refreshed")
        redirect_to profile_path
      end
    end
  end
end
