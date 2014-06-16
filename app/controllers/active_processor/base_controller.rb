# -*- encoding : utf-8 -*-
module ActiveProcessor
  class BaseController < ApplicationController
    layout "callc" #layout ActiveProcessor.configuration.layout
    before_filter :check_post_method_pg, :only => [:pay]
    before_filter :check_localization
    before_filter :check_if_enabled, :only => [:index, :pay], :if => lambda{ not payment_gateway_active? }

    def index
      @gateway = ::GatewayEngine.find(:first, {:engine => params[:engine], :gateway => params[:gateway], :for_user => current_user.id}).enabled_by(current_user.owner.id).query

      unless @gateway
        flash[:notice] = _("Inactive_Gateway")
        redirect_to :controller => "/callc", :action => "main" and return false
      end


      @page_title = @gateway.display_name
      @page_icon = "money.png"

      respond_to do |format|
        format.html {}
      end

    rescue ActiveProcessor::GatewayEngineError # invalid engine or gateway name specified
      flash[:notice] = _("Inactive_Gateway")
      redirect_to :controller => "/callc", :action => "main"
    end

    # GET /pay
    def pay

      @engine = ::GatewayEngine.find(:first, {:engine => params[:engine], :gateway => params[:gateway], :for_user => current_user.id}).enabled_by(current_user.owner.id)
#      @page_title = @engine.display_name
#      @page_icon = "money.png"

      # Custom Notice passed to get response in case of crashing
      respond_to do |format|
        error_notice = ''
        if @engine.pay_with(@engine.query, request.remote_ip, error_notice, params['gateways'])

          format.html {
            flash[:status] = _('Payment_Successful')
            if params[:gateway] == 'paypal'
              custom_redirect = Confline.get_value('gateways_paypal_PayPal_Custom_redirect', current_user.owner.id).to_i
              custom_redirect_successful_payment = Confline.get_value('gateways_paypal_Paypal_return_url', current_user.owner.id)
              if custom_redirect and custom_redirect.to_i == 1
                redirect_to Web_URL + "/" + custom_redirect_successful_payment.to_s
              else
                redirect_to :root
              end
            else
              redirect_to :root
            end

          }
        else
          @gateway = @engine.query
          format.html {
            if (@gateway.errors.size + @gateway.credit_card.errors.size) > 0
              flash.now[:notice] = _('ERRORs') + ":"
            else
              flash.now[:notice] = _('Payment_Error')
              if @gateway.name == "hsbc_secure_epayments"
                if  !@gateway.payment.response.blank?
                  if @gateway.payment.response.params["return_message"]
                    flash.now[:notice] += "<br/> * ".html_safe + @gateway.payment.response.params["return_message"].to_s
                  else
                    flash.now[:notice] += "<br/> * ".html_safe + @gateway.payment.response.params["error_message"].to_s
                  end
                end
                flash.now[:notice] += "<br/> * ".html_safe + error_notice if !error_notice.blank?
              elsif @gateway.name == "paypal"
                flash.now[:notice] += "<br/> * ".html_safe + @gateway.payment.response.message.to_s
              end
            end
            notice_flash_errors(@gateway.credit_card) if @gateway.credit_card.errors.size > 0
            notice_flash_errors(@gateway) if @gateway.errors.size > 0
            render :action => "index"
          }
        end
      end
    end

    def notice_flash_errors(object)
      object.errors.each { |key, value|
        if key.to_s[0..7] == "gateway_"
          key_string = key.to_s
        else
          key_string = "gateway_" + key.to_s
          key_string = "gateway_time" if key_string == "gateway_year"
        end

        flash.now[:notice] += "<br> * #{_(key_string)} - #{value.class == Array ? _(value.first) : _(value)}"
      } if object.respond_to?(:errors)
    end

    # POST /notify
    def notify

    end

    private

    def check_user
      redirect_to :root if !session[:usertype_id] or session[:usertype] == "guest" or session[:usertype].to_s == ""
    end

    def verify_params
      unless params['gateways']
        dont_be_so_smart
        redirect_to :root
      end
    end

    def check_post_method_pg
      unless request.post?
        flash[:notice] = _('Dont_be_so_smart')
        redirect_to :root and return false
      end
    end

    def check_if_enabled
      if admin?
        last_payment = Payment.where("paymenttype NOT IN ('manual', 'credit note', 'invoice', 'voucher', 'subscription', 'Card')").last
        if (last_payment and (last_payment.date_added > (Time.now - 1.day)))
          flash[:notice] = _('payment_gateway_restriction_for_second_time')
          redirect_to :root and return false
        end
      else
        flash[:notice] = _('Dont_be_so_smart')
        redirect_to :root
      end
    end

  end
end
