# frozen_string_literal: true

module Thredded
  # A controller for managing {Post}s.
  class PostsController < Thredded::ApplicationController
    include ActionView::RecordIdentifier
    include Thredded::NewPostParams

    helper_method :topic
    before_action :assign_messageboard_for_actions, only: %i[mark_as_read mark_as_unread]
    after_action :update_user_activity

    after_action :verify_authorized

    def new
      @post_form = Thredded::PostForm.new(
        user: thredded_current_user, topic: parent_topic, post_params: new_post_params
      )
      authorize_creating @post_form.post
    end

    def create
      @post_form = Thredded::PostForm.new(
        user: thredded_current_user, topic: parent_topic, post_params: new_post_params
      )
      authorize_creating @post_form.post

      if @post_form.save
        redirect_to post_path(@post_form.post, user: thredded_current_user)
      else
        render :new
      end
    end

    def edit
      @post_form = Thredded::PostForm.for_persisted(post)
      authorize @post_form.post, :update?
      return redirect_to(canonical_topic_params) unless params_match?(canonical_topic_params)
      render
    end

    def update
      authorize post, :update?
      post.update(new_post_params)

      redirect_to post_path(post, user: thredded_current_user)
    end

    def destroy
      authorize post, :destroy?
      post.destroy!

      redirect_back fallback_location: topic_url(topic),
                    notice: I18n.t('thredded.posts.deleted_notice')
    end

    def mark_as_read
      authorize post, :read?
      UserTopicReadState.touch!(thredded_current_user.id, post)
      respond_to do |format|
        format.html { redirect_back fallback_location: post_path(post, user: thredded_current_user) }
        format.json { render(json: { read: true }) }
      end
    end

    def mark_as_unread
      authorize post, :read?
      post.mark_as_unread(thredded_current_user)
      respond_to do |format|
        format.html { after_mark_as_unread } # customization hook
        format.json { render(json: { read: false }) }
      end
    end

    def quote
      authorize_reading post
      render plain: Thredded::ContentFormatter.quote_content(post.content)
    end
    
      def like
    #current_user.like!(@post)

    if @like = Like.create!(liker_type: "SpreeUser", liker_id: current_user.id, likeable: @post)
      if Socialization::ActiveRecordStores::Like.update_counter(@post, likers_count: +1)
        render json: {
                 type: "success",
                 likers_count: @post.likers_count + 1,
                 data: render_to_string(partial: "thredded/posts/likes", locals: { post: @post }),
               }
      end
    end
  end

  def dislike
    #current_user.unlike!(post)

    if @dislike = Like.find_by(liker_type: "SpreeUser", liker_id: current_user.id, likeable: @post)
      @dislike.destroy
      if Socialization::ActiveRecordStores::Like.update_counter(@post, likers_count: -1)
        render json: {
                 type: "success",
                 likers_count: @post.likers_count - 1,
                 data: render_to_string(partial: "thredded/posts/likes", locals: { post: @post }),
               }
      end

      #redirect_to album_path(@album), notice: "You disliked this post"
    end
  end

    private

    def canonical_topic_params
      { messageboard_id: messageboard.slug, topic_id: topic.slug }
    end

    def after_mark_as_unread
      redirect_to messageboard_topics_path(messageboard)
    end

    def topic
      post.postable
    end

    def parent_topic
      Thredded::Topic
        .where(messageboard: messageboard)
        .friendly_find!(params[:topic_id])
    end

    def assign_messageboard_for_actions
      @messageboard = post.postable.messageboard
    end

    def post
      @post ||= Thredded::Post.find!(params[:id])
    end

    def current_page
      params[:page].nil? ? 1 : params[:page].to_i
    end
  end
end
