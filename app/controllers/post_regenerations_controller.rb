# frozen_string_literal: true

class PostRegenerationsController < ApplicationController
  respond_to :xml, :json, :html

  def create
    @post = authorize Post.find(params[:post_id]), :regenerate?
    @post.regenerate_later!(params[:category], CurrentUser.user)

    respond_with(@post, notice: I18n.t("post_regenerations.flash.scheduled"))
  end
end
