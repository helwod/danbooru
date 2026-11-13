# frozen_string_literal: true

class UserMailer < ApplicationMailer
  # The email sent when a user receives a DMail.
  def dmail_notice(dmail)
    @dmail = dmail
    @user = dmail.to
    mail_user(
      @user,
      from: "#{Danbooru.config.canonical_app_name} <#{Danbooru.config.notification_email}>",
      subject: I18n.t("user_mailer.subjects.dmail_notice", app_name: Danbooru.config.canonical_app_name, name: dmail.from.name),
      require_verified_email: true,
    )
  end

  # The email sent when a user requests a password reset.
  def password_reset(user)
    @user = user
    mail_user(
      @user,
      from: "#{Danbooru.config.canonical_app_name} <#{Danbooru.config.account_security_email}>",
      subject: I18n.t("user_mailer.subjects.password_reset", app_name: Danbooru.config.app_name),
      require_verified_email: false,
    )
  end

  # The email sent when a user changes their email address.
  def email_change_confirmation(user)
    @user = user
    mail_user(
      @user,
      from: "#{Danbooru.config.canonical_app_name} <#{Danbooru.config.account_security_email}>",
      subject: I18n.t("user_mailer.subjects.email_change_confirmation"),
      require_verified_email: false,
    )
  end

  # The email sent when a user logs in from a new location and needs to verify it.
  #
  # @param user_event [UserEvent] The login event that triggered this email.
  def login_verification(user_event)
    @user_event = user_event
    @user = user_event.user

    mail_user(
      @user,
      from: "#{Danbooru.config.canonical_app_name} <#{Danbooru.config.account_security_email}>",
      subject: I18n.t("user_mailer.subjects.login_verification"),
      require_verified_email: false,
    )
  end

  # The email sent when a new user signs up with an email address.
  def welcome_user(user)
    @user = user
    mail_user(
      @user,
      from: "#{Danbooru.config.canonical_app_name} <#{Danbooru.config.welcome_user_email}>",
      subject: I18n.t("user_mailer.subjects.welcome_user", app_name: Danbooru.config.app_name),
      require_verified_email: false,
    )
  end

  # The email sent when an admin sends a user their 2FA backup code.
  def send_backup_code(user)
    @user = user
    @backup_code = user.backup_codes.first

    mail_user(
      @user,
      from: "#{Danbooru.config.canonical_app_name} <#{Danbooru.config.account_security_email}>",
      subject: I18n.t("user_mailer.subjects.send_backup_code"),
      require_verified_email: false,
    )
  end

  def dmca_complaint(to:)
    @dmca = params[:dmca]
    mail(
      from: Danbooru.config.dmca_email,
      to: to,
      subject: I18n.t("user_mailer.subjects.dmca_complaint"),
    )
  end
end
