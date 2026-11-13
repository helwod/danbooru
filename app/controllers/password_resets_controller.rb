# frozen_string_literal: true

class PasswordResetsController < ApplicationController
  respond_to :html, :xml, :json

  verify_captcha only: :create

  rescue_from ActiveSupport::MessageVerifier::InvalidSignature do
    redirect_to password_reset_path, notice: I18n.t("password_resets.flash.invalid_link"), status: 303
  end

  rescue_from Pundit::NotAuthorizedError do
    redirect_to profile_path, notice: I18n.t("password_resets.flash.already_logged_in")
  end

  # Show the password reset request page.
  def show
    authorize CurrentUser.user, policy_class: PasswordResetPolicy
  end

  # Show the change password form.
  def edit
    @user = authorize User.find_by_token_for!(:password_reset, params.dig(:user, :signed_id)), policy_class: PasswordResetPolicy
  end

  # Send the password reset email.
  def create
    name_or_email = params.dig(:user, :name)
    @user = authorize User.find_by_name_or_email(name_or_email), policy_class: PasswordResetPolicy

    @user&.request_password_reset!(request)

    if Danbooru::EmailAddress.is_valid?(name_or_email)
      flash[:notice] = I18n.t("password_resets.flash.email_exists")
    else
      flash[:notice] = I18n.t("password_resets.flash.email_address_exists")
    end

    redirect_to password_reset_path
  end

  # Change the user's password.
  def update
    @user = authorize User.find_by_token_for!(:password_reset, params.dig(:user, :signed_id)), policy_class: PasswordResetPolicy

    success = @user.reset_password(
      new_password: params.dig(:user, :password),
      password_confirmation: params.dig(:user, :password_confirmation),
      verification_code: params.dig(:user, :verification_code),
      request: request,
    )

    if success
      SessionLoader.new(request).login_user(@user, :login)
      notice = I18n.t("password_resets.flash.password_updated")
    end

    respond_with(@user, notice: notice)
  end
end
