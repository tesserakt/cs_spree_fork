# coding: utf-8
require 'spec_helper'

describe "Order Details", js: true do
  let!(:stock_location) { create(:stock_location_with_items) }
  let!(:product) { create(:product, :name => 'spree t-shirt', :price => 20.00) }
  let!(:tote) { create(:product, :name => "Tote", :price => 15.00) }
  let(:order) { create(:order, :state => 'complete', :completed_at => "2011-02-01 12:36:15", :number => "R100") }
  let(:state) { create(:state) }
  let(:shipment) { create(:shipment, :order => order, :stock_location => stock_location) }
  let!(:shipping_method) { create(:shipping_method, :name => "Default") }

  before do
    order.shipments.create(stock_location_id: stock_location.id)
    order.contents.add(product.master, 2)
  end

  context 'as Admin' do
    stub_authorization!


    context "cart edit page" do
      before { visit spree.cart_admin_order_path(order) }


      it "should allow me to edit order details" do
        page.should have_content("spree t-shirt")
        page.should have_content("$40.00")

        within_row(1) do
          click_icon :edit
          fill_in "quantity", :with => "1"
        end
        click_icon :ok

        within("#order_total") do
          page.should have_content("$20.00")
        end
      end

      it "can add an item to a shipment" do
        select2_search "spree t-shirt", :from => Spree.t(:name_or_sku)
        within("table.stock-levels") do
          fill_in "variant_quantity", :with => 2
          click_icon :plus
        end

        within("#order_total") do
          page.should have_content("$80.00")
        end
      end

      it "can remove an item from a shipment" do
        page.should have_content("spree t-shirt")

        within_row(1) do
          accept_alert do
            click_icon :trash
          end
        end

        # Click "ok" on confirmation dialog
        page.should_not have_content("spree t-shirt")
      end

      # Regression test for #3862
      it "can cancel removing an item from a shipment" do
        page.should have_content("spree t-shirt")

        within_row(1) do
          # Click "cancel" on confirmation dialog
          dismiss_alert do
            click_icon :trash
          end
        end

        page.should have_content("spree t-shirt")
      end

      it "can add tracking information" do
        visit spree.edit_admin_order_path(order)

        within(".show-tracking") do
          click_icon :edit
        end
        fill_in "tracking", :with => "FOOBAR"
        click_icon :ok

        page.should_not have_css("input[name=tracking]")
        page.should have_content("Tracking: FOOBAR")
      end

      it "can change the shipping method" do
        order = create(:completed_order_with_totals)
        visit spree.edit_admin_order_path(order)
        within("table.index tr.show-method") do
          click_icon :edit
        end
        select2 "Default", :from => "Shipping Method"
        click_icon :ok

        page.should_not have_css('#selected_shipping_rate_id')
        page.should have_content("Default")
      end

      it "will show the variant sku" do
        order = create(:completed_order_with_totals)
        visit spree.edit_admin_order_path(order)
        sku = order.line_items.first.variant.sku
        expect(page).to have_content("SKU: #{sku}")
      end

      context "with special_instructions present" do
        let(:order) { create(:order, :state => 'complete', :completed_at => "2011-02-01 12:36:15", :number => "R100", :special_instructions => "Very special instructions here") }
        it "will show the special_instructions" do
          visit spree.edit_admin_order_path(order)
          expect(page).to have_content("Very special instructions here")
        end
      end


    end

    context "shipment edit page" do
      before { visit spree.cart_admin_order_path(order) }

      context "variant doesn't track inventory" do
        before do
          tote.master.update_column :track_inventory, false
          # make sure there's no stock level for any item
          tote.master.stock_items.update_all count_on_hand: 0, backorderable: false
        end

        it "adds variant to order just fine"  do
          select2_search tote.name, :from => Spree.t(:name_or_sku)
          within("table.stock-levels") do
            fill_in "variant_quantity", :with => 1
            click_icon :plus
          end

          within(".line-items") do
            page.should have_content(tote.name)
          end
        end
      end

      context "variant out of stock and not backorderable" do
        before do
          product.master.stock_items.first.update_column(:backorderable, false)
          product.master.stock_items.first.update_column(:count_on_hand, 0)
        end

        it "displays out of stock instead of add button" do
          select2_search product.name, :from => Spree.t(:name_or_sku)

          within("table.stock-levels") do
            page.should have_content(Spree.t(:out_of_stock))
          end
        end




      end
    end
  end

  context 'with only read permissions' do
    before do
      Spree::Admin::BaseController.any_instance.stub(:spree_current_user).and_return(nil)
    end

    custom_authorization! do |user|
      can [:admin, :index, :read, :edit], Spree::Order
    end
    it "should not display forbidden links" do
      page.should_not have_button('cancel')
      page.should_not have_button('Resend')

      # Order Tabs
      page.should_not have_link('Order Details')
      page.should_not have_link('Customer Details')
      page.should_not have_link('Adjustments')
      page.should_not have_link('Payments')
      page.should_not have_link('Return Authorizations')

      # Order item actions
      page.should_not have_css('.delete-item')
      page.should_not have_css('.split-item')
      page.should_not have_css('.edit-item')
      page.should_not have_css('.edit-tracking')

      page.should_not have_css('#add-line-item')
    end
  end

  context 'as Fakedispatch' do
    custom_authorization! do |user|
      # allow dispatch to :admin, :index, and :edit on Spree::Order
      can [:admin, :edit, :index, :read], Spree::Order
      # allow dispatch to :index, :show, :create and :update shipments on the admin
      can [:admin, :manage, :read, :ship], Spree::Shipment
    end

    before do
      Spree::Api::BaseController.any_instance.stub :try_spree_current_user => Spree.user_class.new
    end

    it 'should not display order tabs or edit buttons without ability' do
      visit spree.edit_admin_order_path(order)

      # Order Form
      page.should_not have_css('.edit-item')
      # Order Tabs
      page.should_not have_link('Order Details')
      page.should_not have_link('Customer Details')
      page.should_not have_link('Adjustments')
      page.should_not have_link('Payments')
      page.should_not have_link('Return Authorizations')
    end

    it "can add tracking information" do
      visit spree.edit_admin_order_path(order)
      within("table.index tr:nth-child(5)") do
        click_icon :edit
      end
      fill_in "tracking", :with => "FOOBAR"
      click_icon :ok

      page.should_not have_css("input[name=tracking]")
      page.should have_content("Tracking: FOOBAR")
    end

    it "can change the shipping method" do
      order = create(:completed_order_with_totals)
      visit spree.edit_admin_order_path(order)
      within("table.index tr.show-method") do
        click_icon :edit
      end
      select2 "Default", :from => "Shipping Method"
      click_icon :ok

      page.should_not have_css('#selected_shipping_rate_id')
      page.should have_content("Default")
    end

    it 'can ship' do
      order = create(:order_ready_to_ship)
      order.refresh_shipment_rates
      visit spree.edit_admin_order_path(order)
      click_icon 'arrow-right'
      wait_for_ajax
      within '.shipment-state' do
        page.should have_content('SHIPPED')
      end
    end
  end
end
